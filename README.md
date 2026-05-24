# mockaccel-runtime

A small mock **embedded inference-accelerator runtime**: a Linux daemon that pretends to be a neural-network accelerator chip, plus a thin SDK (C++ + Python) that talks to it.

It exists to serve as the **SUT** (*System Under Test* — the program a test framework exercises) for practicing CI/CD, build automation, cross-compilation, and validation tooling against a realistic embedded software shape, without needing real silicon.

The "device" is a process. The "SDK" is a static library plus Python bindings. The whole thing builds in under a minute on a laptop and runs entirely in user space.

## Why this shape

Real embedded inference stacks (TensorRT, OpenVINO, vendor NPU SDKs) share a common architecture:

- a **C++ runtime core** that manages sessions, queues inference requests, and surfaces typed errors
- a **Python wrapper** that most users actually consume
- an **IPC boundary** (PCIe, USB, shared memory) between the host code and the device firmware
- **telemetry** (temperature, utilization, power) and **fault behaviors** (timeouts, throttling, ECC errors)

`mockaccel-runtime` reproduces that *behavior surface* — not the silicon, not real ML — so that a test framework written against it exercises the same patterns as a test framework written against a real device:

- spawning a device-side process, waiting for it to become ready, tearing it down
- request/response correlation over a socket
- mapping wire-level error codes to typed exceptions
- injecting faults to validate error paths
- measuring latency and telemetry under load
- cross-compiling the C++ pieces to a different architecture

## Architecture

```
┌──────────────────────────────────┐
│  test framework / user code      │   Python
│    import pymockaccel as mx      │
└──────────────────────────────────┘
                │
                ▼  pybind11
┌──────────────────────────────────┐
│  pymockaccel                     │   C++ → Python bindings
│  (Device, Model, Telemetry,      │
│   exception hierarchy)           │
└──────────────────────────────────┘
                │
                ▼  C++ method calls
┌──────────────────────────────────┐
│  runtime_core                    │   static C++ library
│   - Client (socket RPC)          │
│   - Device / Model (public API)  │   ← what cross-compiles to ARM64
│   - codec (framing + base64)     │
└──────────────────────────────────┘
                │
                ▼  UNIX domain socket
                │  length-prefixed JSON
┌──────────────────────────────────┐
│  device_simulator                │   standalone C++ daemon
│   - accept loop                  │
│   - model store                  │   ← the fake "chip"
│   - telemetry engine             │
│   - fault injector               │
└──────────────────────────────────┘
```

### Components

| Component | Language | Role |
|---|---|---|
| `device_simulator/` | C++17 | Standalone daemon. Listens on a UNIX socket. Holds loaded models in memory. Returns deterministic fake tensors after a configurable latency. Can be told to inject faults that affect the next inference. |
| `runtime_core/` | C++17 | Static library — the "SDK internals". Owns the socket, frames requests, parses responses, maps wire-level errors to typed C++ exceptions. The public C++ headers in `include/mockaccel/` are what an embedding application would use. |
| `pymockaccel/` | C++ + Python | pybind11 module wrapping `runtime_core`. The Python-side surface that test code imports. |
| `include/mockaccel/` | C++ headers | Public SDK API: `Device`, `Model`, `Telemetry`, the full exception hierarchy. |
| `examples/` | Python | One end-to-end smoke script (`hello.py`) and two example model manifests. |
| `docs/protocol.md` | Markdown | Canonical wire-protocol spec — the source of truth for what the daemon and the SDK agree on. |

### Process model

Two processes, one client at a time:

1. `device_simulator` runs as a long-lived daemon. It owns the UNIX socket file.
2. Any client (the Python smoke script, a pytest fixture, a CLI tool) opens one connection at a time, runs through a session, closes.

Multiple concurrent clients are *not* supported by design — the test framework is the focus, and a single-connection server is easier to reason about. The daemon accepts the next client as soon as the current one disconnects.

### Wire protocol (one-paragraph summary)

UNIX domain socket. Every message is `[4-byte little-endian length][JSON payload]`. Requests carry `op`, `id`, `args`; responses carry `id`, `ok`, and either `result` or `error`. Six ops: `load_model`, `run_inference`, `get_telemetry`, `inject_fault`, `unload_model`, `shutdown`. Full spec in [`docs/protocol.md`](docs/protocol.md).

### Fault model

The daemon understands five fault types injected via `inject_fault`:

| Fault | What the daemon does | What the SDK surfaces |
|---|---|---|
| `clear`            | Cancels any pending fault | n/a |
| `timeout`          | Sleeps past any reasonable client timeout, then returns a timeout error | `TimeoutError` |
| `thermal_throttle` | Spikes telemetry temperature, refuses the next inference | `ThermalThrottleError` |
| `ecc_error`        | Returns an uncorrectable-memory error (ECC = *Error-Correcting Code*, the on-chip memory protection that detects bit flips) | `EccError` |
| `disconnect`       | Drops the socket without responding | `TransportError` |

Each fault is consumed by exactly one inference call, then auto-clears. This is deliberate — it makes faults trivial to parametrize in tests:

```python
@pytest.mark.parametrize("fault,exc", [
    ("timeout",          mx.TimeoutError),
    ("thermal_throttle", mx.ThermalThrottleError),
    ("ecc_error",        mx.EccError),
    ("disconnect",       mx.TransportError),
])
def test_fault(device, model, fault, exc):
    device.inject_fault(fault)
    with pytest.raises(exc):
        model.infer(b"\x00" * 4)
```

### Inference semantics

The daemon does not run a real neural network. For a loaded model with input shape `S_in` and output shape `S_out`:

```
output[i] = input[i] XOR (handle & 0xFF)    # for i in range(min(S_in_bytes, S_out_bytes))
output[i] = 0                                # for any remaining bytes
```

This is deterministic, fast (~microseconds before the simulated latency sleep), and lets golden-file tests work without any ML dependencies. All tensors are flat `uint8` byte buffers — no NumPy on the wire.

### Telemetry semantics

Synthetic values:

- temperature drifts toward a 38 °C baseline; jumps to 95 °C when `thermal_throttle` is injected
- utilization rises by 5% per inference, decays by 1.5% per telemetry read
- power scales linearly with utilization

Enough variation that a test can assert "telemetry changed after N inferences" without being flaky.

## Build

Requirements: `cmake` ≥ 3.20, a C++17 compiler (g++ ≥ 9 or clang ≥ 10), Python 3.8+ with development headers (`python3-dev` on Debian/Ubuntu; included with the system Python on macOS).

First-time configure pulls **nlohmann/json** v3.11.3 and **pybind11** v2.13.6 via CMake **FetchContent** (CMake's built-in mechanism for pulling third-party sources at configure time).

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Produces:

| Artifact | Path |
|---|---|
| Daemon binary | `build/device_simulator/mockaccel_device_simulator` |
| SDK static library | `build/runtime_core/libmockaccel_runtime.a` |
| Python extension | `build/pymockaccel/pymockaccel*.so` |

### CMake options

| Option | Default | Notes |
|---|---|---|
| `MOCKACCEL_BUILD_PYTHON` | `ON`  | Set to `OFF` to skip pybind11 (needed for cross-compilation — the Python bindings do not cross-compile cleanly). |
| `CMAKE_BUILD_TYPE`       | `Release` | Standard CMake build type. |
| `CMAKE_TOOLCHAIN_FILE`   | unset | Point at a cross-compilation toolchain file to build the C++ pieces for another architecture (e.g. ARM64). |

### Vendored dependencies

The build prefers a git **submodule** (a git mechanism for embedding one repo inside another at a pinned commit) at `third_party/pybind11/` if one is present, and only falls back to FetchContent otherwise. To switch to a submodule:

```bash
git submodule add https://github.com/pybind/pybind11.git third_party/pybind11
git -C third_party/pybind11 checkout v2.13.6
```

## Smoke test

```bash
# Terminal 1 — start the daemon
./build/device_simulator/mockaccel_device_simulator

# Terminal 2 — load a model, infer, read telemetry, exercise a fault
PYTHONPATH=build/pymockaccel python3 examples/hello.py
```

Expected output (abridged):

```
connecting to /tmp/mockaccel.sock ...
loading examples/models/tiny.hef ...
  loaded: Model(handle=1, name='tiny')
infer(10203040) -> 11213141
telemetry: Telemetry(temperature_c=38.000000, utilization_pct=3.500000, power_w=1.887500)
injecting thermal_throttle for next inference ...
  caught expected: ThermalThrottleError: device thermally throttled
ok
```

## Repository layout

```
mockaccel-runtime/
├── CMakeLists.txt              top-level build
├── README.md                   this file
├── include/mockaccel/          public C++ headers (SDK surface)
│   ├── device.hpp
│   ├── errors.hpp
│   └── protocol.hpp
├── device_simulator/           the daemon
│   ├── CMakeLists.txt
│   └── src/main.cpp
├── runtime_core/               the C++ SDK
│   ├── CMakeLists.txt
│   └── src/
│       ├── client.{hpp,cpp}    socket RPC
│       ├── codec.{hpp,cpp}     framing + base64
│       └── device.cpp          public API implementation
├── pymockaccel/                Python bindings
│   ├── CMakeLists.txt
│   └── src/bindings.cpp
├── examples/
│   ├── hello.py
│   └── models/
│       ├── tiny.hef            4-byte in, 4-byte out
│       └── fake_yolo.hef       1×3×224×224 in, 1×1000 out
├── docs/
│   └── protocol.md             wire-protocol spec
├── third_party/                vendored deps go here (optional)
└── cmake/                      toolchain files for cross-builds
```

## Deliberate non-goals

- No real neural-network inference. The math is XOR.
- No multi-client support. One connection at a time.
- No authentication, no encryption. Local UNIX socket only.
- No persistence. Loaded models live in process memory.
- No async API. Every call is blocking.

These omissions are intentional — they keep the SUT small enough to read in one sitting while preserving every behavior a test framework needs to exercise.
