// mockaccel/errors.hpp
//
// Exception hierarchy surfaced by runtime_core. The client maps wire-level
// error codes (see protocol.hpp) into these so callers can write
// type-targeted catch blocks.

#pragma once

#include <stdexcept>
#include <string>

namespace mockaccel {

class MockAccelError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class TransportError       : public MockAccelError { using MockAccelError::MockAccelError; };
class ProtocolError        : public MockAccelError { using MockAccelError::MockAccelError; };
class BadRequestError      : public MockAccelError { using MockAccelError::MockAccelError; };
class NotFoundError        : public MockAccelError { using MockAccelError::MockAccelError; };
class TimeoutError         : public MockAccelError { using MockAccelError::MockAccelError; };
class ThermalThrottleError : public MockAccelError { using MockAccelError::MockAccelError; };
class EccError             : public MockAccelError { using MockAccelError::MockAccelError; };
class DeviceInternalError  : public MockAccelError { using MockAccelError::MockAccelError; };

}  // namespace mockaccel
