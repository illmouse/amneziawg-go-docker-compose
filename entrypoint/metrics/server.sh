#!/bin/bash
set -eu

. /entrypoint/lib/env.sh
. /entrypoint/lib/functions.sh

METRICS_FILE="${TMP_DIR}/metrics.prom"

info "Metrics server listening on :${METRICS_PORT}"

while true; do
    {
        printf "HTTP/1.1 200 OK\r\n"
        printf "Content-Type: text/plain; version=0.0.4; charset=utf-8\r\n"
        printf "Connection: close\r\n"
        printf "\r\n"
        cat "$METRICS_FILE" 2>/dev/null || printf "# metrics not yet available\n"
    } | nc -l -p "$METRICS_PORT" > /dev/null
done
