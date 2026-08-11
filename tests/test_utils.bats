#!/usr/bin/env bats
# Unit tests for lib/utils.sh — validation, sanitization, private-IP, JSON
# escaping helpers. Run with: bats tests/  (or `make test`).

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    LIB_DIR="$SCRIPT_DIR/lib"
    VERSION="test"; AUTHOR="test"
    OUTPUT_MODE="human"; QUIET=0; NONINTERACTIVE=0
    COLOR_ENABLED=0; COLORBLIND_SAFE=0; PREFERRED_DNS=""
    CONFIG_FILE="/dev/null"
    HISTORY_FILE="$BATS_TMPDIR/nt_history"
    LOG_FILE="$BATS_TMPDIR/nt_test.log"
    TEMP_DIR="$BATS_TMPDIR"
    MAX_LOG_LINES=1000
    MAX_LOG_SIZE=5242880
    # shellcheck source=../lib/utils.sh
    source "$LIB_DIR/utils.sh"
}

# ─── validate_ip ────────────────────────────────────────────────────────────
@test "validate_ip accepts a normal IPv4 address" {
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_ip rejects an out-of-range octet" {
    run validate_ip "999.1.1.1"
    [ "$status" -eq 1 ]
}

@test "validate_ip rejects garbage" {
    run validate_ip "not-an-ip"
    [ "$status" -eq 1 ]
}

@test "validate_ip accepts loopback IPv6" {
    run validate_ip "::1"
    [ "$status" -eq 0 ]
}

# ─── validate_domain ────────────────────────────────────────────────────────
@test "validate_domain accepts a normal domain" {
    run validate_domain "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_domain accepts localhost" {
    run validate_domain "localhost"
    [ "$status" -eq 0 ]
}

@test "validate_domain rejects a shell-metacharacter payload" {
    run validate_domain "example.com; rm -rf /"
    [ "$status" -eq 1 ]
}

# ─── validate_cidr ──────────────────────────────────────────────────────────
@test "validate_cidr accepts a normal /24" {
    run validate_cidr "192.168.1.0/24"
    [ "$status" -eq 0 ]
}

@test "validate_cidr rejects a prefix over 32" {
    run validate_cidr "192.168.1.0/99"
    [ "$status" -eq 1 ]
}

@test "validate_cidr rejects a missing prefix" {
    run validate_cidr "192.168.1.0"
    [ "$status" -eq 1 ]
}

# ─── validate_url ───────────────────────────────────────────────────────────
@test "validate_url accepts https with query string and fragment" {
    run validate_url "https://example.com/path?x=1&y=2#frag"
    [ "$status" -eq 0 ]
}

@test "validate_url rejects a non-http scheme" {
    run validate_url "ftp://example.com"
    [ "$status" -eq 1 ]
}

# ─── validate_port_range ────────────────────────────────────────────────────
@test "validate_port_range accepts a comma list" {
    run validate_port_range "22,80,443"
    [ "$status" -eq 0 ]
}

@test "validate_port_range accepts a dash range" {
    run validate_port_range "1-1000"
    [ "$status" -eq 0 ]
}

@test "validate_port_range rejects letters" {
    run validate_port_range "ab,cd"
    [ "$status" -eq 1 ]
}

# ─── validate_positive_int ─────────────────────────────────────────────────
@test "validate_positive_int accepts 5" {
    run validate_positive_int "5"
    [ "$status" -eq 0 ]
}

@test "validate_positive_int rejects 0" {
    run validate_positive_int "0"
    [ "$status" -eq 1 ]
}

@test "validate_positive_int rejects non-numeric input" {
    run validate_positive_int "abc"
    [ "$status" -eq 1 ]
}

# ─── sanitize_input ─────────────────────────────────────────────────────────
@test "sanitize_input strips shell metacharacters" {
    result="$(sanitize_input 'host; rm -rf / $(evil) `bad` a|b&c')"
    [[ "$result" != *";"* ]]
    [[ "$result" != *"|"* ]]
    [[ "$result" != *"&"* ]]
    [[ "$result" != *'`'* ]]
    [[ "$result" != *'$'* ]]
    [[ "$result" != *"("* ]]
    [[ "$result" != *")"* ]]
}

@test "sanitize_input leaves a normal hostname untouched" {
    result="$(sanitize_input 'example.com')"
    [ "$result" = "example.com" ]
}

# ─── is_private_ip ──────────────────────────────────────────────────────────
@test "is_private_ip accepts 10.0.0.0/8" {
    run is_private_ip "10.1.2.3"
    [ "$status" -eq 0 ]
}

@test "is_private_ip accepts 192.168.0.0/16" {
    run is_private_ip "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "is_private_ip accepts 172.16.0.0/12 inside the range" {
    run is_private_ip "172.20.5.5"
    [ "$status" -eq 0 ]
}

@test "is_private_ip rejects 172.x outside the private range" {
    run is_private_ip "172.40.5.5"
    [ "$status" -eq 1 ]
}

@test "is_private_ip rejects a public address" {
    run is_private_ip "8.8.8.8"
    [ "$status" -eq 1 ]
}

# ─── json_escape ────────────────────────────────────────────────────────────
@test "json_escape escapes double quotes and backslashes" {
    result="$(json_escape 'say "hi" \ done')"
    [[ "$result" == *'\"hi\"'* ]]
    [[ "$result" == *'\\'* ]]
}

@test "json_escape turns newlines into literal \\n" {
    result="$(json_escape "$(printf 'line1\nline2')")"
    [ "$result" = "line1\\nline2" ]
}
