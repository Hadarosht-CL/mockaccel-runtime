# SPDX-License-Identifier: Apache-2.0

"""End-to-end smoke script for mockaccel-runtime.

Prerequisites:
  1. Build the project:   cmake -S . -B build && cmake --build build -j
  2. Start the simulator: ./build/device_simulator/mockaccel_device_simulator

Run:
  PYTHONPATH=build/pymockaccel python3 examples/hello.py
"""

from __future__ import annotations

import os
import sys

import pymockaccel as ph


def main() -> int:
    socket_path = os.environ.get("MOCKACCEL_SOCKET", "/tmp/mockaccel.sock")
    here = os.path.dirname(os.path.abspath(__file__))
    model_path = os.path.join(here, "models", "tiny.hef")

    print(f"connecting to {socket_path} ...")
    dev = ph.Device.open(socket_path)

    print(f"loading {model_path} ...")
    model = dev.load_model(model_path)
    print(f"  loaded: {model!r}")
    print(f"  input_shape={model.input_shape}  output_shape={model.output_shape}")

    payload = bytes([0x10, 0x20, 0x30, 0x40])
    out = model.infer(payload)
    print(f"infer({payload.hex()}) -> {out.hex()}")

    t = dev.telemetry()
    print(f"telemetry: {t!r}")

    print("injecting thermal_throttle for next inference ...")
    dev.inject_fault(ph.fault.THERMAL_THROTTLE)
    try:
        model.infer(payload)
    except ph.ThermalThrottleError as e:
        print(f"  caught expected: {type(e).__name__}: {e}")

    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
