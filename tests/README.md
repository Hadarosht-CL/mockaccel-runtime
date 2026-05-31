<!-- SPDX-License-Identifier: Apache-2.0 -->

# tests/

Home of the Python test suite for `mockaccel-runtime`.

Run the suite via the project verb, not by invoking `pytest` directly:

```
./scripts/test.sh                  # all suites
./scripts/test.sh --suite pytest   # just this one
BUILD_TYPE=Debug ./scripts/test.sh --suite pytest
```

The verb takes care of activating the project virtual environment at `.venv/`
(populated by `./scripts/bootstrap.sh`) and of exporting `BUILD_TYPE` so
fixtures that care about the C++ build flavor can branch on it.

## Layout

```
tests/
  conftest.py        shared fixtures (see "Fixture API" below)
  unit/              fast, hermetic, no subprocess, no socket
  integration/       spawn the SUT daemon, talk to it via pymockaccel
```

`unit/` tests must not import `pymockaccel`'s native bindings and must not
touch the filesystem outside `tmp_path`. `integration/` tests may do both,
through the fixtures below.

Acronyms used here:

- **SUT** - System Under Test. For us, the `mockaccel_device_simulator`
  daemon plus the `pymockaccel` SDK (Software Development Kit) on top of it.
- **IPC** - Inter-Process Communication. The UNIX-socket protocol the SDK
  uses to talk to the daemon.

## Fixture API (locked in Stage 2, populated in Stage 5)

Three fixtures. Designed up front so test authors do not invent their own
ad-hoc setup. Every fixture lives in `tests/conftest.py`.

### `device_fixture` (session-scoped)

Spawns one `mockaccel_device_simulator` daemon for the whole pytest session,
waits for its UNIX socket to become connectable, yields a handle, and kills
the daemon on session teardown.

```python
@pytest.fixture(scope="session")
def device_fixture(
    tmp_path_factory: pytest.TempPathFactory,
) -> Iterator[DeviceHandle]: ...
```

Yields:

```python
@dataclass(frozen=True)
class DeviceHandle:
    socket_path: Path   # unique per session, under tmp_path_factory
    pid: int            # daemon process id
```

Teardown: `SIGTERM`, wait up to 5 s, `SIGKILL` if still alive. Asserts the
process exited (no zombies left for the next test session).

### `runtime_session` (function-scoped)

Opens a fresh `pymockaccel.Session` against the shared daemon, yields it,
closes it on test teardown. One session per test; the daemon is shared.

```python
@pytest.fixture
def runtime_session(
    device_fixture: DeviceHandle,
) -> Iterator[pymockaccel.Session]: ...
```

Teardown: `session.close()` is idempotent, so it is safe to call even if the
test already closed it.

### `injected_fault` (function-scoped, factory)

A factory the test calls to arm a fault on the daemon for the duration of
the test. Implemented as a factory rather than a parametrized fixture so a
single test can arm, observe, clear, and re-arm a different fault without
restarting anything.

```python
@pytest.fixture
def injected_fault(
    runtime_session: pymockaccel.Session,
) -> Iterator[FaultInjector]: ...

class FaultInjector(Protocol):
    def arm(self, kind: FaultKind) -> None: ...
    def clear(self) -> None: ...
```

`FaultKind` mirrors the five fault types the SUT exposes in
`docs/protocol.md`. Teardown calls `clear()` unconditionally so a leaked
fault from one test cannot bleed into the next.

Typical use with `pytest.mark.parametrize`:

```python
@pytest.mark.parametrize("kind", list(FaultKind))
def test_sdk_surfaces_typed_exception(
    runtime_session: pymockaccel.Session,
    injected_fault: FaultInjector,
    kind: FaultKind,
) -> None:
    injected_fault.arm(kind)
    with pytest.raises(kind.expected_exception):
        runtime_session.run_inference(...)
```

## What lives where

| Concern | Goes in |
|---|---|
| Pure-Python helpers, parsers, math | `tests/unit/` |
| Anything that needs the daemon running | `tests/integration/` |
| New fixture | `tests/conftest.py`, documented in this file |
| Test-only data files | `tests/data/` (create when first needed) |

## Style

- Type-annotated, `mypy --strict` clean.
- One assertion per logical fact; `pytest.raises` for exception assertions.
- No `time.sleep` for synchronization. Poll with a short timeout instead.
- No network. `tmp_path` for any filesystem use.
