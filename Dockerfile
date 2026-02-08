# Use the base image
FROM docker.io/amneziavpn/amneziawg-go:latest

# Install required packages
RUN apk add --no-cache \
    jq \
    squid \
    openssl

# Copy entrypoint files and make them executable
RUN mkdir -p /entrypoint
COPY entrypoint/* /entrypoint/

# Make entrypoint files executable
RUN chmod +x /entrypoint/*.sh

ENTRYPOINT ["/entrypoint/main.sh"]