// SPDX-License-Identifier: Apache-2.0

// pymockaccel/bindings.cpp
//
// Python bindings for the runtime_core SDK. Exposes Device, Model, Telemetry,
// and the typed exception hierarchy. Inputs/outputs are Python `bytes` for
// zero-copy-ish tensor transfer; we don't expose NumPy buffer protocol here
// on purpose — that's an exercise the test framework owner can layer on top
// if they want richer tensor handling.

#include <pybind11/pybind11.h>
#include <pybind11/stl.h>

#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "mockaccel/device.hpp"
#include "mockaccel/errors.hpp"

namespace py = pybind11;
using namespace mockaccel;

namespace {

std::vector<std::uint8_t> bytes_to_vec(const py::bytes& b) {
    std::string s = b;
    return std::vector<std::uint8_t>(
        reinterpret_cast<const std::uint8_t*>(s.data()),
        reinterpret_cast<const std::uint8_t*>(s.data() + s.size()));
}

py::bytes vec_to_bytes(const std::vector<std::uint8_t>& v) {
    return py::bytes(reinterpret_cast<const char*>(v.data()), v.size());
}

}  // namespace

PYBIND11_MODULE(pymockaccel, m) {
    m.doc() = "Mock embedded inference-accelerator SDK — see mockaccel-runtime README.";
    m.attr("__version__") = "0.1.0";

    // -----------------------------------------------------------------------
    // Exception hierarchy. Mirrors mockaccel/errors.hpp.
    // -----------------------------------------------------------------------
    static py::exception<MockAccelError>       exc_base(m,         "MockAccelError");
    static py::exception<TransportError>       exc_transport(m,    "TransportError",       exc_base.ptr());
    static py::exception<ProtocolError>        exc_protocol(m,     "ProtocolError",        exc_base.ptr());
    static py::exception<BadRequestError>      exc_bad_request(m,  "BadRequestError",      exc_base.ptr());
    static py::exception<NotFoundError>        exc_not_found(m,    "NotFoundError",        exc_base.ptr());
    static py::exception<TimeoutError>         exc_timeout(m,      "TimeoutError",         exc_base.ptr());
    static py::exception<ThermalThrottleError> exc_thermal(m,      "ThermalThrottleError", exc_base.ptr());
    static py::exception<EccError>             exc_ecc(m,          "EccError",             exc_base.ptr());
    static py::exception<DeviceInternalError>  exc_internal(m,     "DeviceInternalError",  exc_base.ptr());

    py::register_exception_translator([](std::exception_ptr p) {
        try { if (p) std::rethrow_exception(p); }
        catch (const TransportError& e)       { exc_transport(e.what()); }
        catch (const ProtocolError& e)        { exc_protocol(e.what()); }
        catch (const BadRequestError& e)      { exc_bad_request(e.what()); }
        catch (const NotFoundError& e)        { exc_not_found(e.what()); }
        catch (const TimeoutError& e)         { exc_timeout(e.what()); }
        catch (const ThermalThrottleError& e) { exc_thermal(e.what()); }
        catch (const EccError& e)             { exc_ecc(e.what()); }
        catch (const DeviceInternalError& e)  { exc_internal(e.what()); }
        catch (const MockAccelError& e)       { exc_base(e.what()); }
    });

    // -----------------------------------------------------------------------
    // Telemetry
    // -----------------------------------------------------------------------
    py::class_<Telemetry>(m, "Telemetry")
        .def_readonly("temperature_c",   &Telemetry::temperature_c)
        .def_readonly("utilization_pct", &Telemetry::utilization_pct)
        .def_readonly("power_w",         &Telemetry::power_w)
        .def("__repr__", [](const Telemetry& t) {
            return "Telemetry(temperature_c=" + std::to_string(t.temperature_c) +
                   ", utilization_pct=" + std::to_string(t.utilization_pct) +
                   ", power_w=" + std::to_string(t.power_w) + ")";
        });

    // -----------------------------------------------------------------------
    // Model
    // -----------------------------------------------------------------------
    py::class_<Model>(m, "Model")
        .def_property_readonly("handle",
            [](const Model& m_) { return m_.info().handle; })
        .def_property_readonly("name",
            [](const Model& m_) { return m_.info().name; })
        .def_property_readonly("input_shape",
            [](const Model& m_) { return m_.info().input_shape; })
        .def_property_readonly("output_shape",
            [](const Model& m_) { return m_.info().output_shape; })
        .def("infer",
            [](Model& self, const py::bytes& input) {
                auto out = self.infer(bytes_to_vec(input));
                return vec_to_bytes(out);
            },
            py::arg("input"),
            "Run one inference. `input` must be `bytes` of length matching the model's input shape.")
        .def("unload", &Model::unload)
        .def("__repr__", [](const Model& m_) {
            return "Model(handle=" + std::to_string(m_.info().handle) +
                   ", name='" + m_.info().name + "')";
        });

    // -----------------------------------------------------------------------
    // Device
    // -----------------------------------------------------------------------
    py::class_<Device>(m, "Device")
        .def_static("open", &Device::open,
            py::arg("socket_path") = std::string("/tmp/mockaccel.sock"),
            "Connect to a running device_simulator.")
        .def("load_model", &Device::load_model, py::arg("hef_path"),
            "Load a fake .hef manifest file.")
        .def("telemetry", &Device::telemetry,
            "Read current device telemetry.")
        .def("inject_fault", &Device::inject_fault,
            py::arg("type"), py::arg("duration_ms") = 0,
            "Inject a fault. type in {'clear','timeout','thermal_throttle','ecc_error','disconnect'}.")
        .def("close", &Device::close);

    // Fault-type string constants for ergonomic Python use.
    auto fault = m.def_submodule("fault");
    fault.attr("NONE")             = "clear";
    fault.attr("TIMEOUT")          = "timeout";
    fault.attr("THERMAL_THROTTLE") = "thermal_throttle";
    fault.attr("ECC_ERROR")        = "ecc_error";
    fault.attr("DISCONNECT")       = "disconnect";
}
