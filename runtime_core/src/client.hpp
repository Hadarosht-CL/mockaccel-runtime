// runtime_core/client.hpp — the socket-level RPC client.
// Owns the fd; handles connect, request/response correlation, and translating
// wire-level errors into typed C++ exceptions from mockaccel/errors.hpp.

#pragma once

#include <cstdint>
#include <string>

#include <nlohmann/json.hpp>

namespace mockaccel {

class Client {
public:
    explicit Client(const std::string& socket_path);
    ~Client();

    Client(const Client&)            = delete;
    Client& operator=(const Client&) = delete;

    // Send one request, await one response. Throws on transport failure or
    // when the device returns ok=false (mapped to the matching exception
    // subclass from errors.hpp).
    nlohmann::json call(const std::string& op, nlohmann::json args);

    void close();
    bool is_open() const noexcept { return fd_ >= 0; }

private:
    int           fd_      = -1;
    std::uint64_t next_id_ = 1;
};

}  // namespace mockaccel
