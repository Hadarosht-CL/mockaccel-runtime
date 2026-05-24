// SPDX-License-Identifier: Apache-2.0

// runtime_core/codec.hpp — base64 + length-prefix framing helpers.
// Internal to runtime_core. Mirrors what device_simulator does, kept in sync
// by the protocol spec (docs/protocol.md).

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace mockaccel::codec {

std::string b64_encode(const std::vector<std::uint8_t>& in);
std::vector<std::uint8_t> b64_decode(const std::string& in);

// Length-prefixed read/write on a connected fd. Block until the full message
// is transferred or an error occurs. Return false on EOF / error.
bool recv_message(int fd, std::string& out_payload);
bool send_message(int fd, const std::string& payload);

}  // namespace mockaccel::codec
