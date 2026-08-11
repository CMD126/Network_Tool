#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/scan.sh — Port scan, service/OS version scan, vulnerability check (NSE).
# All three validate their target/ports and warn aggressively (blocking in
# non-interactive mode without --yes) before scanning a non-private address.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# _confirm_public_scan <host>
#   Args: $1 = host about to be scanned
#   Returns: 0 if OK to proceed, 1 if the user declined / --yes was required
#   but absent. Prints the aggressive warning banner when the target is not
#   private.
_confirm_public_scan() {
    local host="$1"
    warn_if_public_target "$host" && return 0
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        if [[ "$CONFIRM_YES" -eq 1 ]]; then
            return 0
        fi
        err "Refusing to scan a public target without --yes."
        return 1
    fi
    echo -ne "  ${YELLOW}Continue anyway? [y/N]:${NC} "
    read -r yn
    [[ "$yn" =~ ^[Yy]$ ]] || return 1
    return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# 11. PORT SCAN
#   Args: none; reads $CLI_TARGET/$CLI_PORTS when $NONINTERACTIVE=1
#   CLI: --port-scan HOST [--ports RANGE] [--yes]
# ═════════════════════════════════════════════════════════════════════════════
port_scan() {
    if ! need nmap; then return 1; fi

    local host="" ports=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        host="$CLI_TARGET"
        ports="${CLI_PORTS:-$DEFAULT_PORTS}"
    else
        host=$(prompt "Target host" "localhost")
        ports=$(prompt "Port range" "$DEFAULT_PORTS")
    fi

    if [[ "$host" != "localhost" ]] && ! validate_host "$host"; then
        err "Invalid host: '$host'"
        return 1
    fi
    if ! validate_port_range "$ports"; then
        err "Invalid port range: '$ports'"
        return 1
    fi
    _confirm_public_scan "$host" || return 1

    log "Port scan → $host:$ports"
    section "Port Scan → $host ($ports)"

    local scan_flag="-sT"
    if [[ $EUID -eq 0 ]]; then
        scan_flag="-sS"
        info "Running SYN scan (root)."
    else
        info "Running TCP connect scan (non-root)."
    fi

    local raw=""
    raw=$(run_with_spinner "Scanning $host..." \
        nmap "$scan_flag" -p "$ports" --open -T4 --max-retries 2 --host-timeout 60s "$host")
    echo "$raw"

    local open_count=""
    open_count=$(echo "$raw" | grep -cE '^[0-9]+/(tcp|udp).*open')
    push_result "Port scan $host — $open_count open ports" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && \
        json_output "port_scan" "$host" "true" "{\"ports\":\"$(json_escape "$ports")\",\"open_count\":${open_count}}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 12. SERVICE VERSION SCAN
#   Args: none; reads $CLI_TARGET/$CLI_PORTS when $NONINTERACTIVE=1
#   CLI: --service-scan HOST [--ports RANGE] [--yes]
# ═════════════════════════════════════════════════════════════════════════════
service_scan() {
    if ! need nmap; then return 1; fi

    local host="" ports=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        host="$CLI_TARGET"
        ports="${CLI_PORTS:-1-1000}"
    else
        host=$(prompt "Target host" "localhost")
        ports=$(prompt "Port range" "1-1000")
    fi

    if [[ "$host" != "localhost" ]] && ! validate_host "$host"; then
        err "Invalid host: '$host'"
        return 1
    fi
    if ! validate_port_range "$ports"; then
        err "Invalid port range: '$ports'"
        return 1
    fi
    _confirm_public_scan "$host" || return 1

    log "Service scan → $host:$ports"
    section "Service Version Scan → $host"

    [[ $EUID -ne 0 ]] && warn "Root recommended for accurate OS detection."

    local raw=""
    raw=$(run_with_spinner "Scanning $host..." \
        nmap -sV -O --open -p "$ports" -T4 --max-retries 1 --host-timeout 120s "$host")
    if [[ -z "$raw" ]]; then
        raw=$(run_with_spinner "Scanning $host (no OS detect)..." \
            nmap -sV --open -p "$ports" -T4 "$host")
    fi
    echo "$raw"

    push_result "Service scan $host" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output_raw "service_scan" "$host" "true" "$raw"
}

# ═════════════════════════════════════════════════════════════════════════════
# 13. VULNERABILITY CHECK (NSE)
#   Args: none; reads $CLI_TARGET/$CLI_PORTS when $NONINTERACTIVE=1
#   CLI: --vuln-check HOST [--ports LIST] --yes
#   Always requires an explicit "yes" — interactively via prompt, or via the
#   --yes flag in CLI mode. Refuses to run otherwise.
# ═════════════════════════════════════════════════════════════════════════════
vuln_check() {
    if ! need nmap; then return 1; fi

    local host="" ports=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        if [[ "$CONFIRM_YES" -ne 1 ]]; then
            err "Vulnerability scanning requires explicit confirmation. Re-run with --yes."
            return 1
        fi
        host="$CLI_TARGET"
        ports="${CLI_PORTS:-22,80,443,8080,3389}"
    else
        warn "Only scan systems you own or have written permission to test."
        echo -ne "  ${YELLOW}Continue? [y/N]:${NC} "
        read -r yn
        [[ "$yn" =~ ^[Yy]$ ]] || return 1
        host=$(prompt "Target host" "localhost")
        ports=$(prompt "Ports to check" "22,80,443,8080,3389")
    fi

    if [[ "$host" != "localhost" ]] && ! validate_host "$host"; then
        err "Invalid host: '$host'"
        return 1
    fi
    if ! validate_port_range "$ports"; then
        err "Invalid port range: '$ports'"
        return 1
    fi
    warn_if_public_target "$host" || true   # informational only; consent already gathered above

    log "Vuln check → $host:$ports"
    section "Vulnerability Check → $host"

    local raw=""
    raw=$(run_with_spinner "Running NSE scripts against $host..." \
        nmap -sV --script=vuln,auth,default -p "$ports" --script-timeout 30s --host-timeout 120s "$host")
    echo "$raw" | grep -v "^|  $" | head -80

    local vuln_count=""
    vuln_count=$(echo "$raw" | grep -ciE 'VULNERABLE')
    push_result "Vuln check $host — $vuln_count possible finding(s)" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output "vuln_check" "$host" "true" "{\"possible_findings\":${vuln_count}}"
}
