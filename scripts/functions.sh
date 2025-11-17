#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[SETUP]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Random number generation functions
get_random_int() {
    local min=$1
    local max=$2
    # Use /dev/urandom for better random numbers and larger range
    echo $(( min + ( $(od -An -N4 -tu4 /dev/urandom) % (max - min + 1) ) ))
}

get_random_junk_size() {
    get_random_int 15 150
}

get_random_header() {
    get_random_int 1 2147483647
}

check_required_files() {
    local script_dir="$1"
    
    if [ ! -f "$script_dir/amneziawg-monitor.sh" ]; then
        error "amneziawg-monitor.sh not found in scripts/ directory"
        return 1
    fi
    
    if [ ! -f "$script_dir/../cron/amneziawg-monitor" ]; then
        error "amneziawg-monitor file not found in cron/ directory"
        return 1
    fi
    
    if [ ! -f "$script_dir/../docker-compose.yaml" ]; then
        error "docker-compose.yaml not found in current directory"
        return 1
    fi
    
    return 0
}