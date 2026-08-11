#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/monitor.sh — Active connections, listening ports, speed test, live
#                   bandwidth monitor.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# ═════════════════════════════════════════════════════════════════════════════
# 17. ACTIVE CONNECTIONS
#   Args: none (CLI: --connections)
# ═════════════════════════════════════════════════════════════════════════════
active_connections() {
    log "Active connections"
    section "Established Connections"

    local raw=""
    raw=$(get_established_connections)
    echo "$raw" | awk -F'|' '{printf "  %-6s %-25s %-25s %s\n", $1, $2, $3, $4}' | head -30

    section "Connection Summary"
    get_connection_summary | head -10

    local count=""
    count=$(echo "$raw" | grep -c .)
    push_result "Active connections — $count" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output "active_connections" "local" "true" "{\"count\":${count}}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 18. LISTENING PORTS
#   Args: none (CLI: --listening)
# ═════════════════════════════════════════════════════════════════════════════
listening_ports() {
    log "Listening ports"
    section "Listening Ports (TCP + UDP)"

    if [[ "$OUTPUT_MODE" != "json" && "$QUIET" -ne 1 ]]; then
        printf "  ${BOLD}%-8s %-30s %s${NC}\n" "Proto" "Address:Port" "Process"
        divider
    fi
    local raw=""
    raw=$(get_listening_ports)
    echo "$raw" | awk -F'|' '{printf "  %-8s %-30s %s\n", $1, $2, $3}' | sort -k2

    local count=""
    count=$(echo "$raw" | grep -c .)
    push_result "Listening ports — $count" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output "listening_ports" "local" "true" "{\"count\":${count}}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 19. SPEED TEST
#   Args: none (CLI: --speed-test [--quiet])
#   BUGFIX: `speed` is now validated as a well-formed non-negative number
#   before it's fed into the awk numeric comparison — an empty or malformed
#   curl result used to crash awk with a syntax error.
# ═════════════════════════════════════════════════════════════════════════════
speed_test() {
    if ! need curl; then return 1; fi

    log "Speed test"
    section "Download Speed Test"

    info "Checking connectivity before testing endpoints..."
    if ! check_connectivity; then
        err "You appear to be offline (no response from 8.8.8.8, 1.1.1.1, 9.9.9.9)."
        push_result "Speed test — offline" "Speed test skipped: no connectivity"
        [[ "$OUTPUT_MODE" == "json" ]] && json_output "speed_test" "none" "false" '{"reason":"offline"}'
        return 1
    fi

    local success=false mbps="" used_url="" url speed
    for url in "${SPEEDTEST_ENDPOINTS[@]}"; do
        info "Testing: $url"
        speed=$(curl -o /dev/null -w "%{speed_download}" -s --max-time 25 "$url" 2>/dev/null)

        if [[ "$speed" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk "BEGIN {exit !($speed > 100)}"; then
            mbps=$(awk "BEGIN {printf \"%.2f\", $speed * 8 / 1000000}")
            ok "${BOLD}${mbps} Mbps${NC}  (${speed} bytes/s)"
            success=true
            used_url="$url"
            break
        else
            warn "Endpoint unreachable or returned malformed data."
        fi
    done

    $success || err "All speed test endpoints failed."

    push_result "Speed test — ${mbps:-N/A} Mbps" "Speed test: ${mbps:-N/A} Mbps via ${used_url:-none}"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        json_output "speed_test" "${used_url:-none}" "$success" "{\"mbps\":\"$(json_escape "${mbps:-}")\"}"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# 20. LIVE BANDWIDTH
#   Args: none; reads $CLI_IFACE/$CLI_SAMPLES when $NONINTERACTIVE=1
#   CLI: --live-bandwidth [IFACE] [--samples N]  (N>0 bounds the loop so the
#   CLI mode actually terminates; interactively it runs until Ctrl+C)
#   BUGFIX: counter deltas are now cross-platform (Linux /sys, macOS/BSD
#   netstat -ib) and negative deltas (counter wrap/reset) are detected and
#   treated as a zero-rate sample instead of printing a bogus huge/negative
#   number.
# ═════════════════════════════════════════════════════════════════════════════
live_bandwidth() {
    local iface interval samples=0
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        iface="${CLI_IFACE:-$(get_default_iface)}"
        interval="${CLI_INTERVAL:-2}"
        samples="${CLI_SAMPLES:-5}"
    else
        iface=$(prompt "Interface to monitor" "$(get_default_iface 2>/dev/null || echo eth0)")
        interval=$(prompt "Refresh interval (seconds)" "2")
    fi

    if ! iface_stats_exist "$iface"; then
        err "Interface '$iface' not found or its stats are unavailable on this platform."
        return 1
    fi
    validate_positive_int "$interval" || interval=2

    log "Live bandwidth → $iface"
    info "Monitoring $iface — press Ctrl+C to stop."
    if [[ "$OUTPUT_MODE" != "json" ]]; then
        echo
        printf "  ${BOLD}%-12s %-20s %-20s %-15s %-15s${NC}\n" \
            "Time" "RX (bytes/s)" "TX (bytes/s)" "RX (Kbps)" "TX (Kbps)"
        divider
    fi

    local prev_rx="" prev_tx=""
    read -r prev_rx prev_tx < <(get_iface_bytes "$iface")
    prev_rx="${prev_rx:-0}"; prev_tx="${prev_tx:-0}"

    local iterations=0
    while true; do
        sleep "$interval"
        local cur_rx="" cur_tx="" ts=""
        read -r cur_rx cur_tx < <(get_iface_bytes "$iface")
        cur_rx="${cur_rx:-$prev_rx}"; cur_tx="${cur_tx:-$prev_tx}"
        ts=$(date '+%H:%M:%S')

        local rx_rate="" tx_rate=""
        if (( cur_rx < prev_rx )) || (( cur_tx < prev_tx )); then
            rx_rate=0; tx_rate=0
            warn "Counter reset/wrap detected on $iface — baseline reset."
        else
            rx_rate=$(( (cur_rx - prev_rx) / interval ))
            tx_rate=$(( (cur_tx - prev_tx) / interval ))
        fi

        local rx_kbps="" tx_kbps=""
        rx_kbps=$(awk "BEGIN {printf \"%.1f\", $rx_rate * 8 / 1000}")
        tx_kbps=$(awk "BEGIN {printf \"%.1f\", $tx_rate * 8 / 1000}")

        if [[ "$OUTPUT_MODE" == "json" ]]; then
            json_output "live_bandwidth" "$iface" "true" \
                "$(printf '{"time":"%s","rx_bytes_s":%d,"tx_bytes_s":%d,"rx_kbps":%s,"tx_kbps":%s}' \
                    "$ts" "$rx_rate" "$tx_rate" "$rx_kbps" "$tx_kbps")"
        else
            printf "  %-12s %-20s %-20s %-15s %-15s\n" "$ts" "$rx_rate" "$tx_rate" "$rx_kbps" "$tx_kbps"
        fi

        prev_rx=$cur_rx; prev_tx=$cur_tx
        iterations=$((iterations + 1))
        if [[ "$NONINTERACTIVE" -eq 1 && $samples -gt 0 && $iterations -ge $samples ]]; then
            break
        fi
    done

    push_result "Live bandwidth $iface" "Monitored $iface for $iterations sample(s)"
}
