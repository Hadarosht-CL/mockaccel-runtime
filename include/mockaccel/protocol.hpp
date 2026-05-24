// mockaccel/protocol.hpp
//
// Shared constants used by both ends of the wire. The protocol itself is
// JSON over a UNIX domain socket with a 4-byte little-endian length prefix
// per message. See docs/protocol.md for the full spec.

#pragma once

#include <cstdint>
#include <string_view>

namespace mockaccel::protocol {

inline constexpr std::uint32_t kMaxMessageBytes = 16u * 1024u * 1024u;  // 16 MiB
inline constexpr std::string_view kDefaultSocketPath = "/tmp/mockaccel.sock";

// Op names. Keep in sync with docs/protocol.md.
namespace op {
inline constexpr std::string_view kLoadModel    = "load_model";
inline constexpr std::string_view kRunInference = "run_inference";
inline constexpr std::string_view kGetTelemetry = "get_telemetry";
inline constexpr std::string_view kInjectFault  = "inject_fault";
inline constexpr std::string_view kUnloadModel  = "unload_model";
inline constexpr std::string_view kShutdown     = "shutdown";
}  // namespace op

// Fault types that the simulator understands. "clear" cancels any active fault.
namespace fault {
inline constexpr std::string_view kNone             = "clear";
inline constexpr std::string_view kTimeout          = "timeout";
inline constexpr std::string_view kThermalThrottle  = "thermal_throttle";
inline constexpr std::string_view kEccError         = "ecc_error";
inline constexpr std::string_view kDisconnect       = "disconnect";
}  // namespace fault

// Wire-level error codes returned in response payloads when ok==false.
// The client maps these to typed exceptions (see errors.hpp).
namespace error_code {
inline constexpr std::string_view kBadRequest       = "bad_request";
inline constexpr std::string_view kNotFound         = "not_found";
inline constexpr std::string_view kTimeout          = "timeout";
inline constexpr std::string_view kThermalThrottle  = "thermal_throttle";
inline constexpr std::string_view kEccError         = "ecc_error";
inline constexpr std::string_view kInternal         = "internal";
}  // namespace error_code

}  // namespace mockaccel::protocol
