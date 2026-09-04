###
# Stage 1: Build amneziawg-go and amneziawg-tools
###
FROM golang:1.25-alpine AS builder

# Pinned upstream versions (AmneziaWG 3.1)
ARG AWG_GO_VERSION=v3.1.20260828
ARG AWG_TOOLS_VERSION=v3.1.20260812

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    gcc \
    musl-dev \
    bash \
    linux-headers

WORKDIR /build

# ---- Build amneziawg-go ----
RUN git clone --depth 1 --branch "${AWG_GO_VERSION}" https://github.com/amnezia-vpn/amneziawg-go.git
WORKDIR /build/amneziawg-go
RUN make

# ---- Build amneziawg-tools ----
WORKDIR /build
RUN git clone --depth 1 --branch "${AWG_TOOLS_VERSION}" https://github.com/amnezia-vpn/amneziawg-tools.git
WORKDIR /build/amneziawg-tools/src
RUN make
RUN make install DESTDIR=/out


###
# Stage 2: Runtime image
###
FROM alpine:latest

ARG AWG_GO_VERSION
ARG AWG_TOOLS_VERSION

LABEL org.opencontainers.image.title="amneziawg-go" \
      org.opencontainers.image.description="AmneziaWG userspace VPN server/client with UDP obfuscation and self-healing" \
      org.opencontainers.image.source="https://github.com/illmouse/amneziawg-go-docker-compose" \
      org.opencontainers.image.licenses="MIT" \
      io.amneziawg-go.version="${AWG_GO_VERSION}" \
      io.amneziawg-tools.version="${AWG_TOOLS_VERSION}"

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    iptables \
    ip6tables \
    jq \
    openssl \
    logrotate \
    3proxy --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing

# Copy amneziawg-go binary
COPY --from=builder /build/amneziawg-go/amneziawg-go /usr/bin/amneziawg-go

# Copy everything installed by amneziawg-tools
COPY --from=builder /out/ /

# Copy entrypoint scripts
RUN mkdir -p /entrypoint
COPY entrypoint/ /entrypoint/
RUN find /entrypoint -name "*.sh" -exec chmod +x {} \;

ENTRYPOINT ["/entrypoint/main.sh"]
