# Use the base image
FROM docker.io/amneziavpn/amneziawg-go:latest

# Install required packages
RUN apk add --no-cache \
    jq \
    openssl \
    3proxy --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing

# Copy entrypoint directory tree and make scripts executable
RUN mkdir -p /entrypoint
COPY entrypoint/ /entrypoint/
RUN find /entrypoint -name "*.sh" -exec chmod +x {} \;

ENTRYPOINT ["/entrypoint/main.sh"]
