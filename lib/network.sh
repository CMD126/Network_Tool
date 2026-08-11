#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/network.sh — Dashboard, interface info, routing table, local discovery,
#                   ping, traceroute, MTU discovery.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# ═════════════════════════════════════════════════════════════════════════════
# 1. DASHBOARD
#   Args: none (CLI: --dashboard)
#   Side effects: prints a one-screen snapshot; pings 3 targets in parallel
# ═════════════════════════════════════════════════════════════════════════════
dashboard() {
    log "Dashboard"
    banner
    section "Public IP"
    local pub_ip=""
    pub_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
          || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
          || echo "unavailable")
    ok "Public IP : ${BOLD}$pub_ip${NC}"

    section "Primary Interface"
    local iface="" gw="" local_ip=""
    iface=$(get_default_iface)
    gw=$(get_default_gateway)
    local_ip=$(get_local_ip "$iface")
    ok "Interface  : ${BOLD}${iface:-unknown}${NC}"
    ok "Local IP   : ${BOLD}${local_ip:-unknown}${NC}"
    ok "Gateway    : ${BOLD}${gw:-unknown}${NC}"

    section "DNS Servers"
    local dns_servers=""
    dns_servers=$(get_dns_servers)
    if [[ -n "$dns_servers" ]]; then
        echo "$dns_servers" | sed 's/^/  /'
    else
        echo "  (could not determine — check /etc/resolv.conf)"
    fi

    section "Connectivity"
    # Ping all targets in parallel (background jobs + wait) rather than serially.
    local targets=(8.8.8.8 1.1.1.1 google.com)
    local ptmp="$TEMP_DIR/dash_ping"
    mkdir -p "$ptmp"
    local t pids=()
    for t in "${targets[@]}"; do
        ( ping -c1 -W2 "$t" >/dev/null 2>&1 && echo up > "$ptmp/$t" || echo down > "$ptmp/$t" ) &
        pids+=($!)
    done
    local p=""
    for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done

    local reachable=0 total=${#targets[@]} conn_json="[" first=1
    for t in "${targets[@]}"; do
        local state=""
        state=$(cat "$ptmp/$t" 2>/dev/null || echo down)
        if [[ "$state" == "up" ]]; then
            ok "  $t  ${GREEN}REACHABLE${NC}"
            reachable=$((reachable + 1))
        else
            err "  $t  ${RED}UNREACHABLE${NC}"
        fi
        [[ $first -eq 0 ]] && conn_json+=","
        conn_json+=$(printf '{"target":"%s","up":%s}' "$(json_escape "$t")" "$( [[ "$state" == "up" ]] && echo true || echo false )")
        first=0
    done
    conn_json+="]"

    section "Open Listening Ports (top 10)"
    get_listening_ports | head -10 | awk -F'|' '{printf "  %-8s %-24s %s\n", $1, $2, $3}'

    local label="Dashboard — ${reachable}/${total} reachable, IP ${local_ip:-?}"
    local human=""
    human="Dashboard snapshot $(date)
Public IP: $pub_ip
Interface: ${iface:-?}  Local IP: ${local_ip:-?}  Gateway: ${gw:-?}
Connectivity: ${reachable}/${total} reachable"
    push_result "$label" "$human"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local data=""
        data=$(printf '{"public_ip":"%s","interface":"%s","local_ip":"%s","gateway":"%s","reachable":%d,"total":%d,"connectivity":%s}' \
            "$(json_escape "$pub_ip")" "$(json_escape "${iface:-}")" "$(json_escape "${local_ip:-}")" \
            "$(json_escape "${gw:-}")" "$reachable" "$total" "$conn_json")
        json_output "dashboard" "local" "true" "$data"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. INTERFACE INFO
#   Args: none (CLI: --interfaces)
# ═════════════════════════════════════════════════════════════════════════════
interface_info() {
    log "Interface info"
    section "Network Interfaces"
    local iface="" state="" addr="" mac=""
    while IFS='|' read -r iface state addr mac; do
        [[ -z "$iface" ]] && continue
        printf "${YELLOW}%-14s${NC} %-8s %-20s MAC: %s\n" "$iface" "$state" "$addr" "${mac:-N/A}"
    done < <(get_interfaces_summary)

    section "Interface Statistics"
    local rx="" tx=""
    while IFS='|' read -r iface rx tx; do
        [[ -z "$iface" ]] && continue
        printf "  %-16s RX: %-14s TX: %s bytes\n" "$iface" "$rx" "$tx"
    done < <(get_interface_stats)

    local raw=""
    raw=$(get_interfaces_summary)
    push_result "Interface info" "$raw"

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local data="[" first=1
        while IFS='|' read -r iface state addr mac; do
            [[ -z "$iface" ]] && continue
            [[ $first -eq 0 ]] && data+=","
            data+=$(printf '{"iface":"%s","state":"%s","addr":"%s","mac":"%s"}' \
                "$(json_escape "$iface")" "$(json_escape "$state")" "$(json_escape "$addr")" "$(json_escape "${mac:-}")")
            first=0
        done < <(get_interfaces_summary)
        data+="]"
        json_output "interface_info" "local" "true" "{\"interfaces\":$data}"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. ROUTING TABLE
#   Args: none (CLI: --routes)
# ═════════════════════════════════════════════════════════════════════════════
routing_table() {
    log "Routing table"
    section "Default Gateway"
    echo "  $(get_default_gateway)"

    section "Full Routing Table"
    get_routing_table

    section "ARP / Neighbour Table"
    get_arp_table

    local raw=""
    raw="$(get_routing_table)
$(get_arp_table)"
    push_result "Routing table" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output_raw "routing_table" "local" "true" "$raw"
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. LOCAL DISCOVERY
#   Args: none, reads $CLI_TARGET when $NONINTERACTIVE=1 (CLI: --discover CIDR)
# ═════════════════════════════════════════════════════════════════════════════
local_discovery() {
    log "Local discovery"
    if ! need nmap; then return 1; fi

    local subnet=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        subnet="${CLI_TARGET:-$(get_local_subnet)}"
    else
        subnet=$(prompt "Subnet to scan (CIDR)" "$(get_local_subnet 2>/dev/null || echo 192.168.1.0/24)")
    fi

    if ! validate_cidr "$subnet"; then
        err "Invalid CIDR: '$subnet'"
        return 1
    fi

    info "Scanning $subnet (ping sweep + ARP)..."
    local raw=""
    raw=$(run_with_spinner "Scanning $subnet..." nmap -sn "$subnet")

    section "Live Hosts"
    echo "$raw" | awk '
        /Nmap scan report/ {
            if (ip != "") { printf "  %-18s %s\n", ip, (mac == "" ? "(no MAC — local host)" : mac) }
            ip=$NF; gsub(/[()]/, "", ip); mac=""
        }
        /MAC Address/ { mac=$0 }
        END { if (ip != "") { printf "  %-18s %s\n", ip, (mac == "" ? "(no MAC — local host)" : mac) } }
    '

    local host_count=""
    host_count=$(echo "$raw" | grep -c "Host is up")
    push_result "Local discovery — $host_count hosts up" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output "local_discovery" "$subnet" "true" "{\"hosts_up\":$host_count}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. PING
#   Args: none; reads $CLI_TARGET/$CLI_COUNT when $NONINTERACTIVE=1
#   CLI: --ping HOST [--count N]
# ═════════════════════════════════════════════════════════════════════════════
ping_host() {
    local host="" count=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        host="$CLI_TARGET"
        count="${CLI_COUNT:-$DEFAULT_PING_COUNT}"
    else
        host=$(prompt "Host to ping" "8.8.8.8")
        count=$(prompt "Packet count" "$DEFAULT_PING_COUNT")
    fi

    if ! validate_host "$host"; then
        err "Invalid host: '$host'"
        return 1
    fi
    validate_positive_int "$count" || count="$DEFAULT_PING_COUNT"

    log "Ping $host x$count"
    section "Ping → $host"

    local raw rc=0
    raw=$(platform_ping "$host" "$count" 2>&1) || rc=$?
    echo "$raw"

    local loss=""
    loss=$(echo "$raw" | grep -Eo '[0-9.]+% packet loss' | grep -Eo '^[0-9.]+' | head -1)
    loss="${loss:-100}"

    if [[ $rc -eq 0 ]]; then
        ok "Ping succeeded — ${loss}% loss"
    else
        err "Ping failed or host unreachable — ${loss}% loss"
    fi

    push_result "Ping $host — ${loss}% loss" "$raw"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local success=""
        [[ $rc -eq 0 ]] && success=true || success=false
        json_output "ping" "$host" "$success" "{\"packet_loss_pct\":${loss},\"count\":${count}}"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. TRACEROUTE
#   Args: none; reads $CLI_TARGET when $NONINTERACTIVE=1
#   CLI: --traceroute HOST
# ═════════════════════════════════════════════════════════════════════════════
trace_route() {
    local host=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        host="$CLI_TARGET"
    else
        host=$(prompt "Target host" "8.8.8.8")
    fi

    if ! validate_host "$host"; then
        err "Invalid host: '$host'"
        return 1
    fi

    log "Traceroute → $host"
    section "Traceroute → $host"

    local raw tool_used=""
    if has traceroute; then
        tool_used="traceroute"
        raw=$(traceroute -m 30 -w 1 -q 1 "$host" 2>&1 || true)
    elif has tracepath; then
        tool_used="tracepath"
        raw=$(tracepath "$host" 2>&1 || true)
    else
        err "Neither traceroute nor tracepath found."
        case "$OS" in
            linux) warn "Install: sudo apt install traceroute" ;;
            macos) warn "Install: brew install inetutils (provides traceroute)" ;;
            *)     warn "Please install traceroute." ;;
        esac
        return 1
    fi
    echo "$raw"

    local hops=""
    hops=$(echo "$raw" | grep -cE '^[[:space:]]*[0-9]+')
    push_result "Traceroute $host — $hops hops ($tool_used)" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output "traceroute" "$host" "true" "{\"tool\":\"$tool_used\",\"hops\":$hops}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. MTU DISCOVERY
#   Args: none; reads $CLI_TARGET when $NONINTERACTIVE=1
#   CLI: --mtu HOST
# ═════════════════════════════════════════════════════════════════════════════
mtu_discovery() {
    local host=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        host="$CLI_TARGET"
    else
        host=$(prompt "Target host" "8.8.8.8")
    fi

    if ! validate_host "$host"; then
        err "Invalid host: '$host'"
        return 1
    fi

    log "MTU discovery → $host"
    section "MTU Discovery → $host"
    info "Probing MTU sizes (this may take ~30 seconds)..."

    local mtu found=0
    for mtu in 1500 1492 1480 1454 1400 1300 1200 576; do
        local result=""
        result=$(platform_ping_df "$host" "$((mtu - 28))")
        if echo "$result" | grep -qE '1( packets)? received'; then
            ok "MTU ${BOLD}${mtu}${NC} bytes — ${GREEN}OK${NC}"
            found=$mtu
            break
        else
            warn "MTU $mtu — too large"
        fi
    done

    local success=""
    if [[ $found -gt 0 ]]; then
        ok "Effective MTU: ${BOLD}${found}${NC}"
        success=true
    else
        err "Could not determine MTU."
        success=false
    fi

    push_result "MTU discovery $host — ${found} bytes" "MTU discovery to $host: $found"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output "mtu_discovery" "$host" "$success" "{\"mtu\":${found}}"
}
