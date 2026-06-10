# SPDX-License-Identifier: Apache-2.0
# Two-stage build: `builder` on `debian:bookworm` runs `scripts/build.sh` with `CMAKE_FLAGS=-DMOCKACCEL_BUILD_PYTHON=OFF`; `runtime` on `debian:bookworm-slim` copies binary, creates non-root `mockaccel` user, sets ENTRYPOINT/CMD per the hint, adds HEALTHCHECK + OCI labels. SPDX header on line 1.

# Builder stage: build the mockaccel binary
FROM debian:bookworm AS builder
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Copy source and run project's build script with python build disabled
COPY . /src
ENV CMAKE_FLAGS=-DMOCKACCEL_BUILD_PYTHON=OFF
RUN chmod +x ./scripts/build.sh && ./scripts/build.sh

# Runtime stage: minimal image that runs the binary as non-root
FROM debian:bookworm-slim
LABEL org.opencontainers.image.title="mockaccel" \
      org.opencontainers.image.description="Mock accelerator runtime" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://gitlab.com/hadarosht-dev/mockaccel-runtime"

RUN useradd -m -u 1000 -U -s /usr/sbin/nologin mockaccel || true

# Copy the built binary from the builder stage. Adjust path if build script writes elsewhere.
COPY --from=builder --chown=mockaccel:mockaccel /src/build/device_simulator/mockaccel_device_simulator /usr/local/bin/mockaccel_device_simulator
RUN mkdir -p /var/run/mockaccel && chown mockaccel:mockaccel /var/run/mockaccel

USER mockaccel
WORKDIR /var/run/mockaccel

# Entry point and default arguments
ENTRYPOINT ["/usr/local/bin/mockaccel_device_simulator"]
CMD ["--socket", "/var/run/mockaccel/mockaccel.sock"]

# Healthcheck ensures binary is present and runnable
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/usr/bin/test", "-S", "/var/run/mockaccel/mockaccel.sock"]