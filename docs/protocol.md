# Wire protocol

Status: stable for v0.x.
Transport: UNIX domain socket, `SOCK_STREAM`. Default path `/tmp/mockaccel.sock`.
Concurrency: one client at a time.

## Framing

Every message — both request and response — is encoded as:

```
[ 4-byte little-endian length ][ JSON payload ]
```

Maximum payload size: 16 MiB (`protocol::kMaxMessageBytes`). Larger messages are dropped and the connection is closed.

## Request shape

```json
{
  "op":   "<operation_name>",
  "id":   <integer, client-chosen, monotonic per connection>,
  "args": { ... }
}
```

## Response shape

Success:

```json
{ "ok": true, "id": <echoed>, "result": { ... } }
```

Error:

```json
{
  "ok": false,
  "id": <echoed>,
  "error": { "code": "<error_code>", "message": "<human readable>" }
}
```

The runtime_core client maps each `code` to a typed C++ exception (see `include/mockaccel/errors.hpp`), and pymockaccel re-exposes those as Python exception classes.

## Operations

### `load_model`

```json
// request
{"op": "load_model", "id": 1, "args": {"path": "/path/to/fake.hef"}}

// response.result
{
  "handle": 1,
  "name": "fake_yolov5",
  "input_shape":  [1, 3, 224, 224],
  "output_shape": [1, 1000]
}
```

The `.hef` file is a JSON manifest. Required fields: `input_shape`, `output_shape`. Optional: `name`, `base_latency_ms` (default 5.0).

### `run_inference`

```json
// request
{"op": "run_inference", "id": 2, "args": {
   "handle": 1,
   "input_b64": "<base64 of the input tensor bytes>"
}}

// response.result
{
  "output_b64": "<base64 of the output tensor bytes>",
  "latency_ms": 8.42
}
```

Input length must equal `product(input_shape)` bytes. Output length equals `product(output_shape)`. Inference is deterministic: `output[i] = input[i] XOR (handle & 0xFF)`, zero-padded or truncated to the output shape.

### `get_telemetry`

```json
// request
{"op": "get_telemetry", "id": 3, "args": {}}

// response.result
{"temperature_c": 38.0, "utilization_pct": 12.5, "power_w": 2.1}
```

Values are synthetic; temperature drifts toward 38°C, utilization decays over time.

### `inject_fault`

```json
{"op": "inject_fault", "id": 4, "args": {"type": "thermal_throttle"}}
```

`type` is one of: `clear`, `timeout`, `thermal_throttle`, `ecc_error`, `disconnect`. The fault affects exactly the next inference, then auto-clears. `disconnect` causes the simulator to drop the socket without sending a response. `clear` cancels any pending fault.

### `unload_model`

```json
{"op": "unload_model", "id": 5, "args": {"handle": 1}}
// response.result: {"ack": true}
```

### `shutdown`

```json
{"op": "shutdown", "id": 6, "args": {}}
// response.result: {"ack": true}
```

The simulator finishes responding and then exits cleanly.

## Error codes

| Code | Meaning | Mapped exception (C++ / Python) |
|---|---|---|
| `bad_request`      | Malformed args, size mismatch, unknown op    | `BadRequestError` |
| `not_found`        | Unknown model handle, missing file           | `NotFoundError` |
| `timeout`          | Device timeout (typically injected)          | `TimeoutError` |
| `thermal_throttle` | Device throttled (typically injected)        | `ThermalThrottleError` |
| `ecc_error`        | Memory ECC failure (injected)                | `EccError` |
| `internal`         | Unexpected server-side condition             | `DeviceInternalError` |
