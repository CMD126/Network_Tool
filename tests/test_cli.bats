#!/usr/bin/env bats
# End-to-end tests for the headless CLI: these run networktool.sh itself and
# check the contract scripts depend on (stdout under --json is pure JSON,
# invalid input is rejected with a non-zero exit before any command runs).

setup() {
    TOOL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/networktool.sh"
    # Keep config/history out of the real home directory.
    export XDG_CONFIG_HOME="$BATS_TMPDIR/nt_xdg"
    ERR_FILE="$BATS_TMPDIR/nt_stderr"
}

# is_single_json_object <text>
#   Succeeds if <text> is exactly one line holding one JSON object.
is_single_json_object() {
    [ "$(printf '%s\n' "$1" | wc -l)" -eq 1 ] || return 1
    printf '%s' "$1" | python3 -c 'import json, sys; d = json.load(sys.stdin); assert isinstance(d, dict)'
}

@test "--json stdout is a single JSON object even though ping prints raw output" {
    out="$(bash "$TOOL" --ping 127.0.0.1 --count 1 --json 2>"$ERR_FILE")" || true
    is_single_json_object "$out"
    [[ "$out" == *'"tool":"ping"'* ]]
    [[ "$out" == *'"target":"127.0.0.1"'* ]]
}

@test "--json output carries the documented top-level keys" {
    out="$(bash "$TOOL" --view-log --json 2>"$ERR_FILE")"
    printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert set(d) == {"tool", "target", "success", "data", "timestamp"}, d.keys()
assert d["tool"] == "view_log"
'
}

@test "an invalid host is rejected: exit 1, nothing on stdout, error on stderr" {
    rc=0
    out="$(bash "$TOOL" --ping 'example.com;id' --json 2>"$ERR_FILE")" || rc=$?
    [ "$rc" -eq 1 ]
    [ -z "$out" ]
    grep -q "Invalid host" "$ERR_FILE"
}

@test "--help prints usage and exits 0" {
    run bash "$TOOL" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI (NON-INTERACTIVE) MODE"* ]]
}
