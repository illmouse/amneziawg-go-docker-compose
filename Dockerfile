###
# Stage 1: Build amneziawg-go and amneziawg-tools
###
FROM golang:1.24-alpine AS builder

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
RUN git clone https://github.com/amnezia-vpn/amneziawg-go.git
WORKDIR /build/amneziawg-go
RUN make

# ---- Build amneziawg-tools ----
WORKDIR /build
RUN git clone https://github.com/amnezia-vpn/amneziawg-tools.git
WORKDIR /build/amneziawg-tools/src
RUN make
RUN make install DESTDIR=/out


###
# Stage 2: Runtime image
###
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    iptables \
    ip6tables \
    jq \
    openssl \
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
