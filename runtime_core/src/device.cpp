// SPDX-License-Identifier: Apache-2.0

// runtime_core/device.cpp — implementation of the public Device/Model API.
// Owns a Client and converts Device::Impl method calls into wire RPCs.

#include "mockaccel/device.hpp"

#include <utility>

#include "client.hpp"
#include "codec.hpp"
#include "mockaccel/protocol.hpp"

namespace mockaccel {

// ---------------------------------------------------------------------------
// Device::Impl
// ---------------------------------------------------------------------------
class Device::Impl {
public:
    explicit Impl(const std::string& socket_path) : client_(socket_path) {}

    Client& client() { return client_; }

private:
    Client client_;
};

// ---------------------------------------------------------------------------
// Device
// ---------------------------------------------------------------------------
Device::Device(std::unique_ptr<Impl> impl) : impl_(std::move(impl)) {}
Device::~Device() = default;

std::unique_ptr<Device> Device::open(const std::string& socket_path) {
    auto impl = std::make_unique<Impl>(socket_path);
    // Private constructor — use a small adapter.
    struct Maker : public Device {
        explicit Maker(std::unique_ptr<Impl> i) : Device(std::move(i)) {}
    };
    return std::unique_ptr<Device>(new Maker(std::move(impl)));
}

Model Device::load_model(const std::string& hef_path) {
    auto result = impl_->client().call(
        std::string(protocol::op::kLoadModel),
        nlohmann::json{{"path", hef_path}});

    ModelInfo info;
    info.handle       = result.at("handle").get<std::uint64_t>();
    info.name         = result.value("name", std::string{});
    info.input_shape  = result.at("input_shape").get<std::vector<int>>();
    info.output_shape = result.at("output_shape").get<std::vector<int>>();
    return Model(*this, std::move(info));
}

Telemetry Device::telemetry() {
    auto r = impl_->client().call(std::string(protocol::op::kGetTelemetry),
                                  nlohmann::json::object());
    Telemetry t;
    t.temperature_c   = r.at("temperature_c").get<double>();
    t.utilization_pct = r.at("utilization_pct").get<double>();
    t.power_w         = r.at("power_w").get<double>();
    return t;
}

void Device::inject_fault(const std::string& type, int duration_ms) {
    impl_->client().call(std::string(protocol::op::kInjectFault),
                         nlohmann::json{{"type", type},
                                        {"duration_ms", duration_ms}});
}

void Device::close() {
    if (impl_) impl_->client().close();
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
Model::Model(Device& device, ModelInfo info)
    : device_(&device), info_(std::move(info)), loaded_(true) {}

Model::~Model() {
    if (loaded_ && device_) {
        try { unload(); } catch (...) { /* destructors must not throw */ }
    }
}

Model::Model(Model&& other) noexcept
    : device_(other.device_), info_(std::move(other.info_)), loaded_(other.loaded_) {
    other.loaded_ = false;
    other.device_ = nullptr;
}

Model& Model::operator=(Model&& other) noexcept {
    if (this != &other) {
        if (loaded_ && device_) { try { unload(); } catch (...) {} }
        device_ = other.device_;
        info_   = std::move(other.info_);
        loaded_ = other.loaded_;
        other.loaded_ = false;
        other.device_ = nullptr;
    }
    return *this;
}

std::vector<std::uint8_t> Model::infer(const std::vector<std::uint8_t>& input) {
    if (!loaded_ || !device_) {
        throw MockAccelError("infer() on unloaded model");
    }
    auto r = device_->impl().client().call(
        std::string(protocol::op::kRunInference),
        nlohmann::json{
            {"handle",    info_.handle},
            {"input_b64", codec::b64_encode(input)},
        });
    return codec::b64_decode(r.at("output_b64").get<std::string>());
}

void Model::unload() {
    if (!loaded_ || !device_) return;
    device_->impl().client().call(
        std::string(protocol::op::kUnloadModel),
        nlohmann::json{{"handle", info_.handle}});
    loaded_ = false;
}

}  // namespace mockaccel
