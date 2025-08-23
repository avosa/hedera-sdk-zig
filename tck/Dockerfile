# Multi-stage Dockerfile for Hedera SDK Zig TCK Server

# Stage 1: Build the TCK server
FROM ubuntu:22.04 AS builder

# Set environment variables
ENV ZIG_VERSION=0.14.1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    build-essential \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
RUN curl -L https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    | tar -xJ -C /usr/local --strip-components=1

# Set working directory
WORKDIR /app

# Copy the entire project (SDK + TCK)
COPY . .

# Build the TCK server
WORKDIR /app/tck
RUN zig build-exe server.zig \
    --deps hedera=/app/src/hedera.zig \
    -O ReleaseSafe \
    --name tck-server

# Stage 2: Runtime image
FROM ubuntu:22.04

# Set environment variables
ENV TCK_PORT=8544
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /bin/false -m tck

# Copy the built TCK server
COPY --from=builder /app/tck/tck-server /usr/local/bin/

# Switch to non-root user
USER tck
WORKDIR /home/tck

# Expose the TCK port
EXPOSE ${TCK_PORT}

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${TCK_PORT}/ || exit 1

# Start the TCK server
CMD ["/usr/local/bin/tck-server"]