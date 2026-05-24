// SPDX-License-Identifier: Apache-2.0

// mockaccel/device.hpp
//
// Public SDK API. This is what runtime_core exposes and what pymockaccel
// wraps for Python. Modelled on a typical embedded inference SDK surface (Device + Model +
// telemetry) without copying any of its internals.

#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "mockaccel/errors.hpp"

namespace mockaccel {

struct Telemetry {
    double temperature_c;
    double utilization_pct;
    double power_w;
};

struct ModelInfo {
    std::uint64_t handle;
    std::string   name;
    std::vector<int> input_shape;
    std::vector<int> output_shape;
};

class Device;  // fwd

// A loaded model. Lifetime is tied to the Device that produced it; unload()
// (or destruction via Device::close) releases the device-side resources.
class Model {
public:
    Model(Device& device, ModelInfo info);
    ~Model();

    Model(const Model&)            = delete;
    Model& operator=(const Model&) = delete;
    Model(Model&&) noexcept;
    Model& operator=(Model&&) noexcept;

    const ModelInfo& info() const noexcept { return info_; }

    // Run one inference. `input` must match the declared input shape
    // (in raw bytes). Returns the output tensor as raw bytes.
    // Throws TimeoutError / ThermalThrottleError / EccError / TransportError.
    std::vector<std::uint8_t> infer(const std::vector<std::uint8_t>& input);

    void unload();

private:
    Device*   device_;
    ModelInfo info_;
    bool      loaded_;
};

class Device {
public:
    // Opens a connection to the device simulator at the given socket path.
    // Throws TransportError on failure.
    static std::unique_ptr<Device> open(
        const std::string& socket_path = "/tmp/mockaccel.sock");

    ~Device();
    Device(const Device&)            = delete;
    Device& operator=(const Device&) = delete;

    // Loads a fake .hef file (JSON manifest) on the device.
    Model load_model(const std::string& hef_path);

    Telemetry telemetry();

    // Injects a fault that affects the next inference(s). `type` must be one
    // of protocol::fault::* values. Pass "clear" to cancel.
    void inject_fault(const std::string& type, int duration_ms = 0);

    void close();

    // Internals reachable to friends — kept public for simplicity since this
    // SDK has a single consumer (Model). A real SDK would use friend or pimpl.
    class Impl;
    Impl& impl() { return *impl_; }

private:
    explicit Device(std::unique_ptr<Impl> impl);
    std::unique_ptr<Impl> impl_;
};

}  // namespace mockaccel
