// device_simulator/main.cpp
//
// Mock embedded inference-accelerator daemon.
//
// Listens on a UNIX domain socket. Accepts one client at a time. Speaks a
// length-prefixed JSON protocol (see docs/protocol.md). Holds loaded "models"
// in memory, returns deterministic fake tensors after a configurable latency,
// and can be told to inject faults.
//
// Single-threaded, blocking I/O — kept simple on purpose. The test framework
// is the focus of the broader project; this binary is the punching bag.

#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include <nlohmann/json.hpp>

#include "mockaccel/protocol.hpp"

namespace proto = mockaccel::protocol;
using nlohmann::json;

// ===========================================================================
// Logging
// ===========================================================================
namespace {

void log_info(const std::string& msg) {
    std::cerr << "[device-sim] " << msg << "\n";
}

void log_warn(const std::string& msg) {
    std::cerr << "[device-sim][warn] " << msg << "\n";
}

void log_error(const std::string& msg) {
    std::cerr << "[device-sim][error] " << msg << "\n";
}

// ===========================================================================
// Base64 (small, dependency-free). Used to ship binary tensors inside JSON.
// ===========================================================================
constexpr char kB64Alphabet[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string b64_encode(const std::vector<std::uint8_t>& in) {
    std::string out;
    out.reserve(((in.size() + 2) / 3) * 4);
    std::size_t i = 0;
    while (i + 3 <= in.size()) {
        std::uint32_t v = (std::uint32_t(in[i]) << 16)
                        | (std::uint32_t(in[i + 1]) << 8)
                        | std::uint32_t(in[i + 2]);
        out.push_back(kB64Alphabet[(v >> 18) & 0x3F]);
        out.push_back(kB64Alphabet[(v >> 12) & 0x3F]);
        out.push_back(kB64Alphabet[(v >> 6)  & 0x3F]);
        out.push_back(kB64Alphabet[v         & 0x3F]);
        i += 3;
    }
    if (i < in.size()) {
        std::uint32_t v = std::uint32_t(in[i]) << 16;
        if (i + 1 < in.size()) v |= std::uint32_t(in[i + 1]) << 8;
        out.push_back(kB64Alphabet[(v >> 18) & 0x3F]);
        out.push_back(kB64Alphabet[(v >> 12) & 0x3F]);
        out.push_back(i + 1 < in.size() ? kB64Alphabet[(v >> 6) & 0x3F] : '=');
        out.push_back('=');
    }
    return out;
}

std::vector<std::uint8_t> b64_decode(const std::string& in) {
    static std::array<int, 256> tbl = []() {
        std::array<int, 256> t{};
        t.fill(-1);
        for (int i = 0; i < 64; ++i) t[static_cast<unsigned char>(kB64Alphabet[i])] = i;
        return t;
    }();

    std::vector<std::uint8_t> out;
    out.reserve((in.size() / 4) * 3);
    std::uint32_t v = 0;
    int bits = 0;
    for (char c : in) {
        if (c == '=' || c == '\n' || c == '\r') continue;
        int d = tbl[static_cast<unsigned char>(c)];
        if (d < 0) throw std::runtime_error("invalid base64");
        v = (v << 6) | static_cast<std::uint32_t>(d);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push_back(static_cast<std::uint8_t>((v >> bits) & 0xFF));
        }
    }
    return out;
}

// ===========================================================================
// Endianness helpers. Wire format is little-endian; on the LE targets we care
// about (x86_64, aarch64) these compile to no-ops.
// ===========================================================================
inline std::uint32_t to_le32(std::uint32_t x) {
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    return x;
#else
    return __builtin_bswap32(x);
#endif
}
inline std::uint32_t from_le32(std::uint32_t x) { return to_le32(x); }

// ===========================================================================
// Length-prefixed framing on a connected socket.
// ===========================================================================
bool read_exact(int fd, void* buf, std::size_t n) {
    auto* p = static_cast<std::uint8_t*>(buf);
    while (n > 0) {
        ssize_t r = ::read(fd, p, n);
        if (r == 0) return false;                 // EOF
        if (r < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        p += r;
        n -= static_cast<std::size_t>(r);
    }
    return true;
}

bool write_exact(int fd, const void* buf, std::size_t n) {
    const auto* p = static_cast<const std::uint8_t*>(buf);
    while (n > 0) {
        ssize_t w = ::write(fd, p, n);
        if (w < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        p += w;
        n -= static_cast<std::size_t>(w);
    }
    return true;
}

bool recv_message(int fd, std::string& out_payload) {
    std::uint32_t len_le = 0;
    if (!read_exact(fd, &len_le, sizeof(len_le))) return false;
    std::uint32_t len = from_le32(len_le);
    if (len == 0 || len > proto::kMaxMessageBytes) return false;
    out_payload.resize(len);
    return read_exact(fd, out_payload.data(), len);
}

bool send_message(int fd, const std::string& payload) {
    if (payload.size() > proto::kMaxMessageBytes) return false;
    std::uint32_t len_le = to_le32(static_cast<std::uint32_t>(payload.size()));
    if (!write_exact(fd, &len_le, sizeof(len_le))) return false;
    return write_exact(fd, payload.data(), payload.size());
}

}  // namespace

// ===========================================================================
// State: loaded models, active fault, telemetry baseline.
// ===========================================================================
namespace {

struct LoadedModel {
    std::uint64_t handle;
    std::string   name;
    std::vector<int> input_shape;
    std::vector<int> output_shape;
    double base_latency_ms;
    std::size_t input_bytes;
    std::size_t output_bytes;
    std::uint8_t xor_seed;
};

struct DeviceState {
    std::unordered_map<std::uint64_t, LoadedModel> models;
    std::uint64_t next_handle = 1;

    // Active fault
    std::string active_fault   = std::string(proto::fault::kNone);
    int         fault_remaining = 0;   // number of inferences still affected

    // Telemetry baseline (drifts over time and with load)
    double      temperature_c   = 38.0;
    double      utilization_pct = 0.0;
    double      power_w         = 1.8;
    std::chrono::steady_clock::time_point started = std::chrono::steady_clock::now();
};

DeviceState g_state;

std::size_t shape_bytes(const std::vector<int>& shape) {
    std::size_t n = 1;
    for (int d : shape) n *= static_cast<std::size_t>(d);
    return n;  // 1 byte per element (uint8 fake tensor)
}

}  // namespace

// ===========================================================================
// Op handlers. Each returns a JSON response object (without the "id" field,
// which the dispatcher adds).
// ===========================================================================
namespace {

json error_response(std::string_view code, const std::string& message) {
    return json{
        {"ok", false},
        {"error", {{"code", std::string(code)}, {"message", message}}},
    };
}

json ok_response(json result) {
    return json{{"ok", true}, {"result", std::move(result)}};
}

json handle_load_model(const json& args) {
    if (!args.contains("path") || !args["path"].is_string()) {
        return error_response(proto::error_code::kBadRequest, "missing 'path'");
    }
    const std::string path = args["path"].get<std::string>();
    std::ifstream f(path);
    if (!f.is_open()) {
        return error_response(proto::error_code::kNotFound, "cannot open " + path);
    }
    json manifest;
    try {
        f >> manifest;
    } catch (const std::exception& e) {
        return error_response(proto::error_code::kBadRequest,
                              std::string("manifest parse: ") + e.what());
    }

    LoadedModel m;
    m.handle = g_state.next_handle++;
    m.name = manifest.value("name", "unnamed");
    m.input_shape  = manifest.value("input_shape",  std::vector<int>{});
    m.output_shape = manifest.value("output_shape", std::vector<int>{});
    m.base_latency_ms = manifest.value("base_latency_ms", 5.0);
    m.input_bytes  = shape_bytes(m.input_shape);
    m.output_bytes = shape_bytes(m.output_shape);
    m.xor_seed = static_cast<std::uint8_t>(m.handle & 0xFF);

    if (m.input_bytes == 0 || m.output_bytes == 0) {
        return error_response(proto::error_code::kBadRequest,
                              "manifest must include non-empty input_shape and output_shape");
    }

    log_info("loaded model handle=" + std::to_string(m.handle) + " name=" + m.name);
    json result{
        {"handle", m.handle},
        {"name",   m.name},
        {"input_shape",  m.input_shape},
        {"output_shape", m.output_shape},
    };
    g_state.models.emplace(m.handle, std::move(m));
    return ok_response(std::move(result));
}

json handle_unload_model(const json& args) {
    if (!args.contains("handle")) {
        return error_response(proto::error_code::kBadRequest, "missing 'handle'");
    }
    auto h = args["handle"].get<std::uint64_t>();
    if (g_state.models.erase(h) == 0) {
        return error_response(proto::error_code::kNotFound, "unknown handle");
    }
    return ok_response(json{{"ack", true}});
}

json handle_run_inference(const json& args) {
    if (!args.contains("handle") || !args.contains("input_b64")) {
        return error_response(proto::error_code::kBadRequest,
                              "missing 'handle' or 'input_b64'");
    }
    auto h = args["handle"].get<std::uint64_t>();
    auto it = g_state.models.find(h);
    if (it == g_state.models.end()) {
        return error_response(proto::error_code::kNotFound, "unknown handle");
    }
    auto& model = it->second;

    // Consume one fault tick if active.
    if (g_state.fault_remaining > 0) {
        g_state.fault_remaining--;
        const auto fault = g_state.active_fault;
        if (g_state.fault_remaining == 0) {
            g_state.active_fault = std::string(proto::fault::kNone);
        }
        if (fault == proto::fault::kTimeout) {
            // Simulate by sleeping past a "client timeout" — actual timeout is
            // enforced by the client. We sleep long enough that any reasonable
            // client gives up first.
            std::this_thread::sleep_for(std::chrono::seconds(5));
            return error_response(proto::error_code::kTimeout, "device timeout");
        }
        if (fault == proto::fault::kThermalThrottle) {
            g_state.temperature_c = 95.0;
            return error_response(proto::error_code::kThermalThrottle,
                                  "device thermally throttled");
        }
        if (fault == proto::fault::kEccError) {
            return error_response(proto::error_code::kEccError,
                                  "uncorrectable ECC error in tensor memory");
        }
        // kDisconnect handled at dispatch level — see below.
    }

    // Decode input, validate size.
    std::vector<std::uint8_t> input;
    try {
        input = b64_decode(args["input_b64"].get<std::string>());
    } catch (const std::exception& e) {
        return error_response(proto::error_code::kBadRequest,
                              std::string("invalid input_b64: ") + e.what());
    }
    if (input.size() != model.input_bytes) {
        return error_response(proto::error_code::kBadRequest,
                              "input size " + std::to_string(input.size()) +
                              " != expected " + std::to_string(model.input_bytes));
    }

    // "Inference": XOR with the model seed, then truncate or zero-pad to
    // match the output shape. Deterministic; fine for golden tests.
    auto start = std::chrono::steady_clock::now();
    std::vector<std::uint8_t> output(model.output_bytes, 0);
    const std::size_t copy = std::min(input.size(), output.size());
    for (std::size_t i = 0; i < copy; ++i) {
        output[i] = static_cast<std::uint8_t>(input[i] ^ model.xor_seed);
    }
    // Sleep to simulate compute latency.
    auto sleep_ms = static_cast<int>(model.base_latency_ms);
    std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms));

    auto elapsed = std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - start).count();

    // Bump utilization a bit; it relaxes in get_telemetry.
    g_state.utilization_pct = std::min(100.0, g_state.utilization_pct + 5.0);

    return ok_response(json{
        {"output_b64",  b64_encode(output)},
        {"latency_ms",  elapsed},
    });
}

json handle_get_telemetry(const json&) {
    // Relax utilization, drift temperature toward baseline.
    g_state.utilization_pct = std::max(0.0, g_state.utilization_pct - 1.5);
    if (g_state.temperature_c > 38.0) g_state.temperature_c -= 0.5;
    g_state.power_w = 1.8 + (g_state.utilization_pct / 100.0) * 2.5;
    return ok_response(json{
        {"temperature_c",   g_state.temperature_c},
        {"utilization_pct", g_state.utilization_pct},
        {"power_w",         g_state.power_w},
    });
}

json handle_inject_fault(const json& args) {
    if (!args.contains("type") || !args["type"].is_string()) {
        return error_response(proto::error_code::kBadRequest, "missing 'type'");
    }
    const std::string type = args["type"].get<std::string>();
    int duration = args.value("duration_ms", 0);  // currently unused; kept for API stability
    (void)duration;

    if (type == proto::fault::kNone) {
        g_state.active_fault = std::string(proto::fault::kNone);
        g_state.fault_remaining = 0;
    } else if (type == proto::fault::kTimeout ||
               type == proto::fault::kThermalThrottle ||
               type == proto::fault::kEccError ||
               type == proto::fault::kDisconnect) {
        g_state.active_fault = type;
        g_state.fault_remaining = 1;  // affects exactly the next inference
    } else {
        return error_response(proto::error_code::kBadRequest, "unknown fault type");
    }
    log_info("injected fault: " + g_state.active_fault);
    return ok_response(json{{"ack", true}});
}

}  // namespace

// ===========================================================================
// Per-connection dispatch loop.
// ===========================================================================
namespace {

// Returns false if the simulator should shut down after this connection.
bool serve_connection(int client_fd, std::atomic<bool>& shutdown_requested) {
    std::string payload;
    while (recv_message(client_fd, payload)) {
        json req;
        try {
            req = json::parse(payload);
        } catch (const std::exception& e) {
            log_warn(std::string("parse error: ") + e.what());
            json err = error_response(proto::error_code::kBadRequest,
                                      std::string("parse: ") + e.what());
            err["id"] = nullptr;
            send_message(client_fd, err.dump());
            continue;
        }

        auto id = req.value("id", json(nullptr));
        std::string op = req.value("op", "");
        json args = req.value("args", json::object());

        // Disconnect fault: drop the socket without responding.
        if (g_state.active_fault == proto::fault::kDisconnect &&
            g_state.fault_remaining > 0) {
            g_state.fault_remaining--;
            if (g_state.fault_remaining == 0) {
                g_state.active_fault = std::string(proto::fault::kNone);
            }
            log_warn("simulating disconnect");
            return true;  // close the connection, keep serving
        }

        json resp;
        if      (op == proto::op::kLoadModel)    resp = handle_load_model(args);
        else if (op == proto::op::kRunInference) resp = handle_run_inference(args);
        else if (op == proto::op::kGetTelemetry) resp = handle_get_telemetry(args);
        else if (op == proto::op::kInjectFault)  resp = handle_inject_fault(args);
        else if (op == proto::op::kUnloadModel)  resp = handle_unload_model(args);
        else if (op == proto::op::kShutdown) {
            shutdown_requested.store(true);
            resp = ok_response(json{{"ack", true}});
            resp["id"] = id;
            send_message(client_fd, resp.dump());
            return false;
        } else {
            resp = error_response(proto::error_code::kBadRequest, "unknown op: " + op);
        }

        resp["id"] = id;
        if (!send_message(client_fd, resp.dump())) {
            log_warn("send failed; closing connection");
            return true;
        }
    }
    return true;
}

}  // namespace

// ===========================================================================
// Main: parse args, create listening socket, accept loop.
// ===========================================================================
namespace {

std::atomic<bool> g_shutdown{false};

void on_signal(int) { g_shutdown.store(true); }

struct Args {
    std::string socket_path = std::string(proto::kDefaultSocketPath);
    bool        print_help  = false;
};

Args parse_args(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; ++i) {
        std::string v = argv[i];
        if (v == "--socket" && i + 1 < argc) {
            a.socket_path = argv[++i];
        } else if (v == "--help" || v == "-h") {
            a.print_help = true;
        } else if (v == "--version") {
            std::cout << "mockaccel_device_simulator 0.1.0\n";
            std::exit(0);
        } else {
            std::cerr << "unknown argument: " << v << "\n";
            std::exit(2);
        }
    }
    return a;
}

void print_help() {
    std::cout <<
        "mockaccel_device_simulator\n"
        "\n"
        "Usage:\n"
        "  mockaccel_device_simulator [--socket PATH]\n"
        "\n"
        "Options:\n"
        "  --socket PATH   UNIX socket path (default: /tmp/mockaccel.sock)\n"
        "  --version       Print version and exit\n"
        "  --help, -h      Show this help\n";
}

}  // namespace

int main(int argc, char** argv) {
    Args args = parse_args(argc, argv);
    if (args.print_help) { print_help(); return 0; }

    signal(SIGINT,  on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);

    // Create UNIX listening socket.
    ::unlink(args.socket_path.c_str());
    int listen_fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        log_error(std::string("socket(): ") + std::strerror(errno));
        return 1;
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    if (args.socket_path.size() >= sizeof(addr.sun_path)) {
        log_error("socket path too long");
        return 1;
    }
    std::strncpy(addr.sun_path, args.socket_path.c_str(), sizeof(addr.sun_path) - 1);

    if (::bind(listen_fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        log_error(std::string("bind(): ") + std::strerror(errno));
        return 1;
    }
    ::chmod(args.socket_path.c_str(), 0660);

    if (::listen(listen_fd, 4) < 0) {
        log_error(std::string("listen(): ") + std::strerror(errno));
        return 1;
    }

    log_info("listening on " + args.socket_path);

    while (!g_shutdown.load()) {
        int client_fd = ::accept(listen_fd, nullptr, nullptr);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            log_error(std::string("accept(): ") + std::strerror(errno));
            break;
        }
        log_info("client connected");
        bool keep_running = serve_connection(client_fd, g_shutdown);
        ::close(client_fd);
        log_info("client disconnected");
        if (!keep_running) break;
    }

    ::close(listen_fd);
    ::unlink(args.socket_path.c_str());
    log_info("shutting down");
    return 0;
}
