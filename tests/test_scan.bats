#!/usr/bin/env bats
# Stub Nmap so finding and error behavior are deterministic and offline.

setup() {
    TOOL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/networktool.sh"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    export NSE_XML='<nmaprun><runstats><finished exit="success"/></runstats></nmaprun>'
    export NSE_RC=0
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/nmap" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-oX" ]]; then
        printf '%s' "$NSE_XML" > "$2"
        shift
    fi
    shift
done
echo 'NOT VULNERABLE; documentation mentions VULNERABLE'
exit "$NSE_RC"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/nmap"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "NSE JSON counts structured findings without matching NOT VULNERABLE prose" {
    export NSE_XML='<nmaprun><host><hostscript><script id="test" output="NOT VULNERABLE"><table key="CVE-A"><elem key="state">VULNERABLE</elem></table><table key="CVE-B"><elem key="state">NOT VULNERABLE</elem></table></script></hostscript></host><runstats><finished exit="success"/></runstats></nmaprun>'
    out="$(bash "$TOOL" --vuln-check 127.0.0.1 --yes --json)"
    printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["success"] is True; assert d["data"]["possible_findings"] == 1'
}

@test "successful NSE run with no structured findings reports zero" {
    out="$(bash "$TOOL" --vuln-check 127.0.0.1 --yes --json)"
    printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["success"] is True; assert d["data"]["possible_findings"] == 0'
}

@test "Nmap command failure returns nonzero and success false without a count" {
    export NSE_RC=2
    rc=0
    out="$(bash "$TOOL" --vuln-check 127.0.0.1 --yes --json 2>/dev/null)" || rc=$?
    [ "$rc" -eq 1 ]
    printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["success"] is False; assert "possible_findings" not in d["data"]'
}

@test "malformed NSE XML returns nonzero and success false without a count" {
    export NSE_XML='<nmaprun>'
    rc=0
    out="$(bash "$TOOL" --vuln-check 127.0.0.1 --yes --json 2>/dev/null)" || rc=$?
    [ "$rc" -eq 1 ]
    printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["success"] is False; assert "possible_findings" not in d["data"]'
}
