# Use the base image
FROM amneziavpn/amneziawg-go:0.2.15

# Install required packages
RUN apk add --no-cache \
    jq \
    squid

# Copy entrypoint files and make them executable
RUN mkdir -p /entrypoint
COPY entrypoint/* /entrypoint/

# Make entrypoint files executable
RUN chmod +x /entrypoint/*.sh

ENTRYPOINT ["/entrypoint/main.sh"]