#!/usr/bin/env bats
# Regression tests for input-handling hardening: strict port/IPv6/interface
# validation, config values that reach bash arithmetic, and output escaping.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    LIB_DIR="$SCRIPT_DIR/lib"
    TOOL="$SCRIPT_DIR/networktool.sh"
    VERSION="test"; AUTHOR="test"
    OUTPUT_MODE="human"; QUIET=0; NONINTERACTIVE=0
    COLOR_ENABLED=0; COLORBLIND_SAFE=0; PREFERRED_DNS=""
    DEFAULT_PING_COUNT=4; DEFAULT_PORTS="1-1000"; DEFAULT_TIMEOUT=10
    SPEEDTEST_ENDPOINTS=("https://default.example/10MB.bin")
    WORK="$(mktemp -d "$BATS_TMPDIR/nt_sec.XXXXXX")"
    CONFIG_FILE="$WORK/config.ini"
    HISTORY_FILE="$WORK/history"
    LOG_FILE="$WORK/test.log"
    TEMP_DIR="$WORK"
    MAX_LOG_LINES=1000
    MAX_LOG_SIZE=5242880
    # shellcheck source=../lib/utils.sh
    source "$LIB_DIR/utils.sh"
    detect_os
    MARKER="$WORK/injected"
}

# refute <cmd...>: fail the test if <cmd> succeeds. (A bare `! cmd` does not
# fail a bats test, because errexit ignores negated commands.)
refute() {
    if "$@"; then
        echo "expected failure: $*" >&2
        return 1
    fi
}

teardown() {
    rm -rf "$WORK"
}

# ─── validate_port / validate_port_range ───────────────────────────────────
@test "validate_port accepts 1 and 65535" {
    validate_port 1
    validate_port 65535
}

@test "validate_port rejects 0, 65536 and non-numbers" {
    refute validate_port 0
    refute validate_port 65536
    refute validate_port "-1"
    refute validate_port "80a"
}

@test "validate_port_range accepts mixed lists and ranges" {
    validate_port_range "22,80,443-445,8080"
    validate_port_range "1-65535"
}

@test "validate_port_range rejects malformed lists that used to pass" {
    local bad
    for bad in "-" "," "80," ",80" "-100" "80-" "1--2" "1-2-3" "1-70000" "0" "100-1" ""; do
        if validate_port_range "$bad"; then
            echo "accepted: '$bad'" >&2
            return 1
        fi
    done
}

# ─── IPv6 ──────────────────────────────────────────────────────────────────
@test "validate_ip accepts well-formed IPv6 addresses" {
    validate_ip "2001:db8::1"
    validate_ip "fe80::1"
    validate_ip "2001:0db8:0000:0000:0000:ff00:0042:8329"
    validate_ip "::"
}

@test "validate_ip rejects colon-only and malformed IPv6" {
    local bad
    for bad in ":" ":::" "1::2::3" "12345::1" "1:2:3:4:5:6:7:8:9" "1:2:3" "1:2:3:4:5:6:7::8:9"; do
        if validate_ip "$bad"; then
            echo "accepted: '$bad'" >&2
            return 1
        fi
    done
}

@test "validate_ip treats a zero-padded octet as decimal, not octal" {
    run validate_ip "192.168.010.009"
    [ "$status" -eq 0 ]
    [ -z "$output" ]   # no 'value too great for base' error
}

# ─── interface names ───────────────────────────────────────────────────────
@test "validate_iface accepts common interface names" {
    validate_iface eth0
    validate_iface en0
    validate_iface wlp2s0
    validate_iface br-1a2b3c
}

@test "validate_iface rejects path traversal and option-like names" {
    refute validate_iface "../../../tmp"
    refute validate_iface "eth0/../x"
    refute validate_iface "-i"
    refute validate_iface ""
}

# ─── config values reaching bash arithmetic ────────────────────────────────
@test "load_config refuses an arithmetic-injection payload in log_max_size" {
    printf 'log_max_size = OS[$(touch %s)]\n' "$MARKER" > "$CONFIG_FILE"
    load_config 2>/dev/null
    [ "$MAX_LOG_SIZE" = "5242880" ]
    log "trigger rotation check"
    [ ! -e "$MARKER" ]
}

@test "load_config warns about an invalid value and keeps the default" {
    printf 'ping_count = lots\n' > "$CONFIG_FILE"
    run load_config
    [[ "$output" == *"ignoring invalid ping_count"* ]]
    load_config 2>/dev/null
    [ "$DEFAULT_PING_COUNT" = "4" ]
}

@test "load_config normalises zero-padded integers to base 10" {
    printf 'ping_count = 010\ntimeout = 7\n' > "$CONFIG_FILE"
    load_config
    [ "$DEFAULT_PING_COUNT" = "10" ]
    [ "$DEFAULT_TIMEOUT" = "7" ]
}

@test "load_config drops speed-test endpoints that are not http(s) URLs" {
    printf 'speed_test_endpoints = https://a.example/f.bin, -K/etc/passwd ,file:///etc/shadow\n' > "$CONFIG_FILE"
    load_config 2>/dev/null
    [ "${#SPEEDTEST_ENDPOINTS[@]}" -eq 1 ]
    [ "${SPEEDTEST_ENDPOINTS[0]}" = "https://a.example/f.bin" ]
}

@test "--samples with an arithmetic payload is rejected and never evaluated" {
    rc=0
    XDG_CONFIG_HOME="$WORK/xdg" bash "$TOOL" --live-bandwidth lo --interval 1 \
        --samples "OS[\$(touch $MARKER)]" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 1 ]
    [ ! -e "$MARKER" ]
}

# ─── output escaping ───────────────────────────────────────────────────────
@test "printable neutralises terminal escapes and echo -e sequences" {
    result="$(printable $'\e[31mred\\e[0m')"
    [[ "$result" != *$'\e'* ]]
    # echo -e must print the backslash literally, not interpret it
    shown="$(echo -e "$result")"
    [[ "$shown" == *'\e[0m'* ]]
    [[ "$shown" != *$'\e'* ]]
}

@test "json_escape output stays valid JSON when input has control characters" {
    esc="$(json_escape $'a\e[1mb\x01c\td\ne')"
    printf '{"v":"%s"}' "$esc" | python3 -c 'import json, sys; json.load(sys.stdin)'
}

@test "sanitize_input also strips redirection characters" {
    result="$(sanitize_input 'host>out<in')"
    [ "$result" = "hostoutin" ]
}
