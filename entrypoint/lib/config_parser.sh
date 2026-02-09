#!/bin/bash
# Shared WireGuard configuration parsing and building utilities.
# Eliminates duplication between client config assembly and monitor failover.

# Extract a single parameter value from a WireGuard .conf file.
# Usage: conf_get_value "PrivateKey" "/path/to/peer.conf"
conf_get_value() {
    local param="$1"
    local config_file="$2"
    grep -E "^${param}[[:space:]]*=" "$config_file" 2>/dev/null \
        | head -1 \
        | sed "s/^${param}[[:space:]]*=[[:space:]]*//" \
        | tr -d '\r\n'
}

# Build a client WireGuard config from a peer template file.
# Extracts [Interface] params, ensures obfuscation params I1-I5,
# then copies [Peer] sections (stripping Address and DNS lines).
# Usage: build_client_config "/path/to/peer_template.conf" "/path/to/output.conf"
build_client_config() {
    local peer_config="$1"
    local output_config="$2"

    if [ -z "$peer_config" ] || [ ! -f "$peer_config" ]; then
        error "Cannot build config from invalid peer template: $peer_config"
        return 1
    fi

    debug "Building client config from: $(basename "$peer_config")"

    # --- Extract parameters ---------------------------------------------------
    local params="PrivateKey Jc Jmin Jmax S1 S2 H1 H2 H3 H4 I1 I2 I3 I4 I5 Address"
    declare -A extracted_params

    for param in $params; do
        local value
        value=$(conf_get_value "$param" "$peer_config")
        if [ -n "$value" ]; then
            extracted_params["$param"]="$value"
        fi
    done

    # --- Ensure I1-I5 obfuscation parameters ----------------------------------
    if [[ -z "${extracted_params[I1]+_}" ]]; then
        extracted_params["I1"]=$(get_protocol_value)
    fi
    for i in {2..5}; do
        local key="I$i"
        if [[ -z "${extracted_params[$key]+_}" || -z "${extracted_params[$key]}" ]]; then
            extracted_params["$key"]=$(generate_cps_value)
        fi
    done

    # --- Write [Interface] section --------------------------------------------
    cat > "$output_config" << EOF
[Interface]
PrivateKey = ${extracted_params[PrivateKey]}
ListenPort = 0
EOF

    for param in Jc Jmin Jmax S1 S2 H1 H2 H3 H4 I1 I2 I3 I4 I5; do
        if [[ -n "${extracted_params[$param]+_}" ]]; then
            printf "%s = %s\n" "$param" "${extracted_params[$param]}" >> "$output_config"
        fi
    done

    echo "" >> "$output_config"

    # --- Append [Peer] sections (skip Address/DNS) ----------------------------
    local in_peer_section=false
    local peer_buffer=""

    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf "%s" "$line" | tr -d '\r')

        if [ "$line" = "[Peer]" ]; then
            if [ "$in_peer_section" = true ] && [ -n "$peer_buffer" ]; then
                echo "$peer_buffer" >> "$output_config"
                echo "" >> "$output_config"
            fi
            peer_buffer="[Peer]"
            in_peer_section=true
        elif [ "$in_peer_section" = true ]; then
            if [ -n "$line" ] && echo "$line" | grep -qE '^\[[a-zA-Z]+\]'; then
                echo "$peer_buffer" >> "$output_config"
                echo "" >> "$output_config"
                peer_buffer=""
                in_peer_section=false
            elif [ -n "$line" ] && ! echo "$line" | grep -qE '^(Address|DNS)'; then
                peer_buffer="$peer_buffer"$'\n'"$line"
            fi
        fi
    done < "$peer_config"

    if [ -n "$peer_buffer" ]; then
        echo "$peer_buffer" >> "$output_config"
    fi

    return 0
}
