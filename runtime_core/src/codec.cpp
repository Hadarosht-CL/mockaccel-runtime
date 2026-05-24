// SPDX-License-Identifier: Apache-2.0

#include "codec.hpp"

#include <unistd.h>

#include <array>
#include <cerrno>
#include <stdexcept>

#include "mockaccel/protocol.hpp"

namespace mockaccel::codec {

namespace {

constexpr char kB64Alphabet[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

inline std::uint32_t to_le32(std::uint32_t x) {
#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    return x;
#else
    return __builtin_bswap32(x);
#endif
}
inline std::uint32_t from_le32(std::uint32_t x) { return to_le32(x); }

bool read_exact(int fd, void* buf, std::size_t n) {
    auto* p = static_cast<std::uint8_t*>(buf);
    while (n > 0) {
        ssize_t r = ::read(fd, p, n);
        if (r == 0) return false;
        if (r < 0) { if (errno == EINTR) continue; return false; }
        p += r;
        n -= static_cast<std::size_t>(r);
    }
    return true;
}

bool write_exact(int fd, const void* buf, std::size_t n) {
    const auto* p = static_cast<const std::uint8_t*>(buf);
    while (n > 0) {
        ssize_t w = ::write(fd, p, n);
        if (w < 0) { if (errno == EINTR) continue; return false; }
        p += w;
        n -= static_cast<std::size_t>(w);
    }
    return true;
}

}  // namespace

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
    static const std::array<int, 256> tbl = []() {
        std::array<int, 256> t{};
        t.fill(-1);
        for (int i = 0; i < 64; ++i) {
            t[static_cast<unsigned char>(kB64Alphabet[i])] = i;
        }
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

bool recv_message(int fd, std::string& out_payload) {
    std::uint32_t len_le = 0;
    if (!read_exact(fd, &len_le, sizeof(len_le))) return false;
    std::uint32_t len = from_le32(len_le);
    if (len == 0 || len > protocol::kMaxMessageBytes) return false;
    out_payload.resize(len);
    return read_exact(fd, out_payload.data(), len);
}

bool send_message(int fd, const std::string& payload) {
    if (payload.size() > protocol::kMaxMessageBytes) return false;
    std::uint32_t len_le = to_le32(static_cast<std::uint32_t>(payload.size()));
    if (!write_exact(fd, &len_le, sizeof(len_le))) return false;
    return write_exact(fd, payload.data(), payload.size());
}

}  // namespace mockaccel::codec
