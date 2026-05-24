// SPDX-License-Identifier: Apache-2.0

#include "client.hpp"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>

#include "codec.hpp"
#include "mockaccel/errors.hpp"
#include "mockaccel/protocol.hpp"

namespace mockaccel {

namespace {

[[noreturn]] void throw_from_error(const std::string& code, const std::string& message) {
    namespace ec = protocol::error_code;
    if (code == ec::kBadRequest)      throw BadRequestError(message);
    if (code == ec::kNotFound)        throw NotFoundError(message);
    if (code == ec::kTimeout)         throw TimeoutError(message);
    if (code == ec::kThermalThrottle) throw ThermalThrottleError(message);
    if (code == ec::kEccError)        throw EccError(message);
    if (code == ec::kInternal)        throw DeviceInternalError(message);
    throw MockAccelError("unknown error code '" + code + "': " + message);
}

}  // namespace

Client::Client(const std::string& socket_path) {
    fd_ = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd_ < 0) {
        throw TransportError(std::string("socket(): ") + std::strerror(errno));
    }
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    if (socket_path.size() >= sizeof(addr.sun_path)) {
        ::close(fd_); fd_ = -1;
        throw TransportError("socket path too long");
    }
    std::strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);
    if (::connect(fd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        int saved = errno;
        ::close(fd_); fd_ = -1;
        throw TransportError("connect(" + socket_path + "): " + std::strerror(saved));
    }
}

Client::~Client() { close(); }

void Client::close() {
    if (fd_ >= 0) {
        ::close(fd_);
        fd_ = -1;
    }
}

nlohmann::json Client::call(const std::string& op, nlohmann::json args) {
    if (fd_ < 0) throw TransportError("client is closed");

    const std::uint64_t id = next_id_++;
    nlohmann::json req = {
        {"op",   op},
        {"id",   id},
        {"args", std::move(args)},
    };

    if (!codec::send_message(fd_, req.dump())) {
        close();
        throw TransportError("send failed for op " + op);
    }

    std::string payload;
    if (!codec::recv_message(fd_, payload)) {
        close();
        throw TransportError("recv failed for op " + op);
    }

    nlohmann::json resp;
    try {
        resp = nlohmann::json::parse(payload);
    } catch (const std::exception& e) {
        close();
        throw ProtocolError(std::string("response parse: ") + e.what());
    }

    // ID correlation is single-request-in-flight, so we just sanity-check.
    if (!resp.contains("id") || resp["id"] != id) {
        // Not fatal — log-and-continue would be reasonable, but here we treat
        // it as a protocol violation.
        throw ProtocolError("response id mismatch");
    }

    if (!resp.value("ok", false)) {
        const auto& err = resp.value("error", nlohmann::json::object());
        throw_from_error(err.value("code", "internal"),
                         err.value("message", "(no message)"));
    }
    return resp.value("result", nlohmann::json::object());
}

}  // namespace mockaccel
