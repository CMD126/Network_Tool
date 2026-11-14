#!/usr/bin/env bash
# tests/run_tests.sh — plain-shell fallback test runner for environments
# without bats-core installed. Covers the same helpers as tests/*.bats.
# Usage: bash tests/run_tests.sh   (or: make test)
# Exit code: 0 if every assertion passed, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

VERSION="test"; AUTHOR="test"
OUTPUT_MODE="human"; QUIET=0; NONINTERACTIVE=0
COLOR_ENABLED=0; COLORBLIND_SAFE=0; PREFERRED_DNS=""
DEFAULT_TIMEOUT=10
CONFIG_FILE="/dev/null"
HISTORY_FILE="$TMP/history"
LOG_FILE="$TMP/test.log"
TEMP_DIR="$TMP"
MAX_LOG_LINES=1000
MAX_LOG_SIZE=5242880

# shellcheck source=../lib/utils.sh
source "$LIB_DIR/utils.sh"
# shellcheck source=../lib/web.sh
source "$LIB_DIR/web.sh"

PASS=0
FAIL=0

assert_status() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok   - $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL - $desc (expected status $expected, got $actual)"
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok   - $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL - $desc (expected '$expected', got '$actual')"
    fi
}

assert_true() {
    local desc="$1" cond="$2"
    if [[ "$cond" -eq 1 ]]; then
        PASS=$((PASS + 1))
        echo "  ok   - $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL - $desc"
    fi
}

echo "== validate_ip =="
validate_ip "192.168.1.1"; assert_status "accepts normal IPv4" 0 $?
validate_ip "999.1.1.1"; assert_status "rejects out-of-range octet" 1 $?
validate_ip "not-an-ip"; assert_status "rejects garbage" 1 $?
validate_ip "::1"; assert_status "accepts IPv6 loopback" 0 $?

echo "== validate_domain =="
validate_domain "example.com"; assert_status "accepts normal domain" 0 $?
validate_domain "localhost"; assert_status "accepts localhost" 0 $?
validate_domain "example.com; rm -rf /"; assert_status "rejects metacharacter payload" 1 $?

echo "== validate_cidr =="
validate_cidr "192.168.1.0/24"; assert_status "accepts /24" 0 $?
validate_cidr "192.168.1.0/99"; assert_status "rejects prefix > 32" 1 $?
validate_cidr "192.168.1.0"; assert_status "rejects missing prefix" 1 $?

echo "== validate_url =="
validate_url "https://example.com/path?x=1&y=2#frag"; assert_status "accepts query+fragment+&" 0 $?
validate_url "ftp://example.com"; assert_status "rejects non-http scheme" 1 $?

echo "== validate_port_range =="
validate_port_range "22,80,443"; assert_status "accepts comma list" 0 $?
validate_port_range "1-1000"; assert_status "accepts dash range" 0 $?
validate_port_range "ab,cd"; assert_status "rejects letters" 1 $?

echo "== validate_positive_int =="
validate_positive_int "5"; assert_status "accepts 5" 0 $?
validate_positive_int "0"; assert_status "rejects 0" 1 $?
validate_positive_int "abc"; assert_status "rejects non-numeric" 1 $?

echo "== sanitize_input =="
result="$(sanitize_input 'host; rm -rf / $(evil) `bad` a|b&c')"
bad=0
for ch in ';' '|' '&' '`' '$' '(' ')'; do
    [[ "$result" == *"$ch"* ]] && bad=1
done
assert_true "strips all shell metacharacters" "$((1 - bad))"
result2="$(sanitize_input 'example.com')"
assert_eq "leaves a normal hostname untouched" "example.com" "$result2"

echo "== is_private_ip =="
is_private_ip "10.1.2.3"; assert_status "accepts 10.0.0.0/8" 0 $?
is_private_ip "192.168.1.1"; assert_status "accepts 192.168.0.0/16" 0 $?
is_private_ip "172.20.5.5"; assert_status "accepts 172.16/12 in-range" 0 $?
is_private_ip "172.40.5.5"; assert_status "rejects 172.x out-of-range" 1 $?
is_private_ip "8.8.8.8"; assert_status "rejects public address" 1 $?

echo "== json_escape =="
esc="$(json_escape 'say "hi" \ done')"
case "$esc" in
    *'\"hi\"'*) PASS=$((PASS + 1)); echo "  ok   - escapes double quotes" ;;
    *) FAIL=$((FAIL + 1)); echo "  FAIL - escapes double quotes (got: $esc)" ;;
esac
nl_esc="$(json_escape "$(printf 'line1\nline2')")"
assert_eq "turns newlines into literal \\n" 'line1\nline2' "$nl_esc"

echo "== parse_cert_date =="
e1="$(parse_cert_date "Jan 1 00:00:00 2030 GMT")"
assert_true "parses a well-formed date (epoch > 0)" "$([[ "$e1" -gt 0 ]] && echo 1 || echo 0)"
e2="$(parse_cert_date "Jun  1 12:00:00 2025 GMT")"
assert_true "handles openssl's double-space single-digit day" "$([[ "$e2" -gt 0 ]] && echo 1 || echo 0)"
e0="$(parse_cert_date "")"
assert_eq "returns 0 for empty input" "0" "$e0"

echo
echo "─────────────────────────────────────"
echo "Passed: $PASS   Failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
