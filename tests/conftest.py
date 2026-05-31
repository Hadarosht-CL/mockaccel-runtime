# SPDX-License-Identifier: Apache-2.0
"""Shared pytest fixtures and session hooks for mockaccel-runtime tests.

The three fixtures here (device_fixture, runtime_session, injected_fault)
form the test framework's public API. Stage 2 ships them as typed stubs
that call pytest.skip() with a clear message; Stage 5 replaces the bodies
with the real setup, teardown, and SUT interaction.

See tests/README.md for the design rationale and intended use.
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Protocol, TypeAlias, cast

import pytest

# pymockaccel is the SUT's Python SDK. Its concrete types land alongside
# the real fixture bodies in Stage 5; until then we alias the Session
# type to Any so mypy --strict has something to bind to. tests/README.md
# documents the intended concrete shape.
PymockaccelSession: TypeAlias = Any

# --- public types ---------------------------------------------------------


@dataclass(frozen=True)
class DeviceHandle:
    """Handle to the daemon spawned by device_fixture.

    socket_path is unique per pytest session; pid is the OS process id of
    the daemon. Both fields are immutable for the lifetime of the session.
    """

    socket_path: Path
    pid: int


class FaultKind(str, Enum):
    """Mirror of the fault types the SUT exposes.

    Values are placeholders synced against docs/protocol.md when Stage 5
    lands; their Stage 2 role is to give mypy and ruff something concrete
    to check sketched test bodies against. The (str, Enum) base keeps us
    compatible with Python 3.10 (StrEnum is 3.11+).
    """

    DEVICE_BUSY = "device_busy"
    TIMEOUT = "timeout"
    INVALID_TENSOR = "invalid_tensor"
    ECC_ERROR = "ecc_error"
    HARDWARE_FAULT = "hardware_fault"


class FaultInjector(Protocol):
    """Test-facing handle for arming and clearing daemon faults.

    A Protocol (not a concrete class) so unit tests can substitute a fake
    without inheriting from anything.
    """

    def arm(self, kind: FaultKind) -> None: ...
    def clear(self) -> None: ...


# --- fixtures (Stage 2 stubs; populated in Stage 5) -----------------------
#
# Every stub is shaped as a yield-fixture so its Stage 5 successor can add
# teardown without changing the public signature. The yield after the skip
# is unreachable today; it exists so the function is a generator and pytest
# treats it as a yield-fixture from day one.

_STAGE5_SKIP_REASON = "fixture body lands in Stage 5; Stage 2 ships only the typed stub"


@pytest.fixture(scope="session")
def device_fixture(
    tmp_path_factory: pytest.TempPathFactory,
) -> Iterator[DeviceHandle]:
    """Spawn the mockaccel daemon once per session."""
    del tmp_path_factory  # consumed by Stage 5's real implementation
    pytest.skip(_STAGE5_SKIP_REASON)
    yield DeviceHandle(socket_path=Path("/dev/null"), pid=0)


@pytest.fixture
def runtime_session(
    device_fixture: DeviceHandle,
) -> Iterator[PymockaccelSession]:
    """Open a fresh pymockaccel.Session against the shared daemon."""
    del device_fixture  # consumed by Stage 5's real implementation
    pytest.skip(_STAGE5_SKIP_REASON)
    yield cast(PymockaccelSession, None)


@pytest.fixture
def injected_fault(
    runtime_session: PymockaccelSession,
) -> Iterator[FaultInjector]:
    """Factory for arming and clearing daemon faults inside a test."""
    del runtime_session  # consumed by Stage 5's real implementation
    pytest.skip(_STAGE5_SKIP_REASON)
    yield cast(FaultInjector, None)


# --- session hooks --------------------------------------------------------


def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    """Treat 'no tests collected' as success while the suite is empty.

    Stage 2's acceptance is that the framework collects zero tests and
    exits 0. Pytest's default exit code for an empty collection is 5
    ('no tests ran'), so we override it here. Remove this hook once
    Stage 5 lands real tests and zero collection means something went
    wrong.
    """
    if exitstatus == pytest.ExitCode.NO_TESTS_COLLECTED:
        session.exitstatus = 0


def pytest_report_header(config: pytest.Config) -> str:
    """Surface the BUILD_TYPE the matrix runner is exercising.

    scripts/test.sh (step 8) exports BUILD_TYPE before invoking pytest so
    the GitLab CI parallel:matrix becomes meaningful. Printing it in the
    pytest header makes matrix-failure triage obvious from the log alone.
    """
    del config  # required by the hook signature; unused
    build_type = os.environ.get("BUILD_TYPE", "<unset>")
    return f"mockaccel BUILD_TYPE: {build_type}"
