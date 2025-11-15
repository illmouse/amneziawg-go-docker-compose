FROM amneziavpn/amneziawg-go:0.2.15

# Install dependencies
RUN apk add --no-cache jq bash

# Create directory structure
RUN mkdir -p /entrypoint /var/log/amneziawg

# Copy all entrypoint scripts
COPY ./entrypoint/ /entrypoint/

# Set execute permissions
RUN chmod +x /entrypoint/*.sh

# Set the main entrypoint script
ENTRYPOINT ["/entrypoint/main.sh"]