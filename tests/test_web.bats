#!/usr/bin/env bats
# Unit tests for lib/web.sh — specifically parse_cert_date, the cross-platform
# (GNU date -d / BSD date -j) certificate expiry parser bugfix.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    LIB_DIR="$SCRIPT_DIR/lib"
    VERSION="test"; AUTHOR="test"
    OUTPUT_MODE="human"; QUIET=0; NONINTERACTIVE=0
    COLOR_ENABLED=0; COLORBLIND_SAFE=0
    DEFAULT_TIMEOUT=10
    CONFIG_FILE="/dev/null"
    HISTORY_FILE="$BATS_TMPDIR/nt_history"
    LOG_FILE="$BATS_TMPDIR/nt_test.log"
    TEMP_DIR="$BATS_TMPDIR"
    MAX_LOG_LINES=1000
    MAX_LOG_SIZE=5242880
    # shellcheck source=../lib/utils.sh
    source "$LIB_DIR/utils.sh"
    # shellcheck source=../lib/web.sh
    source "$LIB_DIR/web.sh"
}

@test "parse_cert_date parses a well-formed openssl date" {
    epoch="$(parse_cert_date "Jan 1 00:00:00 2030 GMT")"
    [ "$epoch" -gt 0 ]
}

@test "parse_cert_date handles openssl's double-space single-digit day" {
    # openssl pads single-digit days with an extra space: "Jun  1 ...".
    epoch="$(parse_cert_date "Jun  1 12:00:00 2025 GMT")"
    [ "$epoch" -gt 0 ]
}

@test "parse_cert_date returns 0 for empty input" {
    epoch="$(parse_cert_date "")"
    [ "$epoch" -eq 0 ]
}

@test "parse_cert_date produces a later epoch for a later year" {
    e1="$(parse_cert_date "Jan 1 00:00:00 2030 GMT")"
    e2="$(parse_cert_date "Jan 1 00:00:00 2031 GMT")"
    [ "$e2" -gt "$e1" ]
}
