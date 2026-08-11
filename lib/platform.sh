#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/platform.sh — Cross-platform abstraction layer. Every OS-specific
#                    command lives behind a get_/platform_ function here so
#                    feature modules (lib/network.sh, lib/monitor.sh, ...)
#                    never branch on $OS themselves.
# Sourced by networktool.sh. Not meant to be executed directly. Requires $OS
# to already be set by detect_os (see lib/utils.sh).
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# get_default_iface
#   Returns: prints the name of the interface used for the default route
get_default_iface() {
    case "$OS" in
        linux)       ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' ;;
        macos|bsd)   route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}' ;;
        *)           echo "" ;;
    esac
}

# get_default_gateway
#   Returns: prints the default gateway IP
get_default_gateway() {
    case "$OS" in
        linux)       ip route show default 2>/dev/null | awk '/default/ {print $3; exit}' ;;
        macos|bsd)   route -n get default 2>/dev/null | awk '/gateway:/ {print $2; exit}' ;;
        *)           echo "" ;;
    esac
}

# get_local_ip <iface>
#   Args: $1 = interface name
#   Returns: prints the primary IPv4 address (CIDR form on Linux, plain on BSD)
get_local_ip() {
    local iface="$1"
    [[ -z "$iface" ]] && return 1
    case "$OS" in
        linux)       ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2; exit}' ;;
        macos|bsd)   ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2; exit}' ;;
        *)           echo "" ;;
    esac
}

# get_routing_table
#   Returns: prints the full routing table (raw, OS-native format)
get_routing_table() {
    case "$OS" in
        linux)       ip route show ;;
        macos|bsd)   netstat -rn ;;
        *)           echo "unsupported OS" ;;
    esac
}

# get_arp_table
#   Returns: prints the ARP / neighbour table (raw, OS-native format)
get_arp_table() {
    case "$OS" in
        linux)       ip neigh show 2>/dev/null | sort -k3 ;;
        macos|bsd)   arp -a 2>/dev/null ;;
        *)           echo "unsupported OS" ;;
    esac
}

# get_interfaces_summary
#   Returns: prints "iface|state|addr|mac" lines for every interface with an
#   IPv4 address, normalized across platforms.
get_interfaces_summary() {
    case "$OS" in
        linux)
            ip addr show 2>/dev/null | awk '
                /^[0-9]+:/ {
                    split($0, a, ": "); iface=a[2]; gsub(/@.*/, "", iface); mac=""; state="UNKNOWN"
                    if (match($0, /state [A-Z]+/)) { state=substr($0, RSTART+6, RLENGTH-6) }
                }
                /link\/ether/ { mac=$2 }
                /inet / { printf "%s|%s|%s|%s\n", iface, state, $2, mac }
            '
            ;;
        macos|bsd)
            ifconfig 2>/dev/null | awk '
                /^[a-zA-Z0-9]+:/ {
                    iface=$1; sub(/:$/, "", iface)
                    state="DOWN"
                    if ($0 ~ /<UP,/ || $0 ~ /<UP>/) state="UP"
                    mac=""
                }
                /ether / { mac=$2 }
                /inet / { printf "%s|%s|%s|%s\n", iface, state, $2, mac }
            '
            ;;
        *) echo "unsupported OS" ;;
    esac
}

# get_interface_stats
#   Returns: prints "iface|rx_bytes|tx_bytes" lines, resilient to variable
#   spacing/column-order differences between tool versions.
get_interface_stats() {
    case "$OS" in
        linux)
            ip -s link 2>/dev/null | awk '
                /^[0-9]+:/ {
                    if (iface != "" && rx != "" && tx != "") printf "%s|%s|%s\n", iface, rx, tx
                    split($0, a, ": "); iface=a[2]; gsub(/@.*/, "", iface)
                    rx=""; tx=""; mode=""
                    next
                }
                /^[[:space:]]*RX:/ { mode="rx"; next }
                /^[[:space:]]*TX:/ { mode="tx"; next }
                mode=="rx" && rx=="" { rx=$1; mode=""; next }
                mode=="tx" && tx=="" { tx=$1; mode=""; next }
                END { if (iface != "" && rx != "" && tx != "") printf "%s|%s|%s\n", iface, rx, tx }
            '
            ;;
        macos|bsd)
            netstat -ib 2>/dev/null | awk '
                NR==1 {
                    for (i=1;i<=NF;i++) { if ($i=="Ibytes") ib=i; if ($i=="Obytes") ob=i }
                    next
                }
                ib && ob && $ib ~ /^[0-9]+$/ { print $1"|"$ib"|"$ob }
            ' | sort -u -t'|' -k1,1
            ;;
        *) echo "unsupported OS" ;;
    esac
}

# get_iface_bytes <iface>
#   Args: $1 = interface name
#   Returns: prints "rx_bytes tx_bytes" for the given interface
get_iface_bytes() {
    local iface="$1"
    case "$OS" in
        linux)
            local rx="" tx=""
            rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null) || return 1
            tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null) || return 1
            echo "$rx $tx"
            ;;
        macos|bsd)
            netstat -ib 2>/dev/null | awk -v ifc="$iface" '
                NR==1 { for (i=1;i<=NF;i++) { if ($i=="Ibytes") ib=i; if ($i=="Obytes") ob=i }; next }
                $1==ifc && ib && $ib ~ /^[0-9]+$/ { print $ib, $ob; exit }
            '
            ;;
        *) return 1 ;;
    esac
}

# iface_stats_exist <iface>
#   Returns: 0 if the interface can be monitored on this platform
iface_stats_exist() {
    local iface="$1"
    case "$OS" in
        linux) [[ -f "/sys/class/net/$iface/statistics/rx_bytes" ]] ;;
        macos|bsd) [[ -n "$(get_iface_bytes "$iface")" ]] ;;
        *) return 1 ;;
    esac
}

# platform_ping <host> <count>
#   Args: $1 = host, $2 = packet count
#   Returns: runs ping with sane cross-platform flags, prints its output
platform_ping() {
    local host="$1" count="$2"
    case "$OS" in
        linux)     ping -c "$count" -i 0.2 -W 2 "$host" ;;
        macos|bsd) ping -c "$count" -i 0.2 "$host" ;;
        *)         ping -c "$count" "$host" ;;
    esac
}

# platform_ping_df <host> <payload_size>
#   Args: $1 = host, $2 = ICMP payload size in bytes
#   Returns: sends a single "don't fragment" ping of the given size, used for
#   MTU discovery. Exit code / output follow the underlying ping.
platform_ping_df() {
    local host="$1" size="$2"
    case "$OS" in
        linux)     ping -M do -s "$size" -c1 -W2 "$host" 2>&1 ;;
        macos|bsd) ping -D -s "$size" -c1 "$host" 2>&1 ;;
        *)         ping -c1 "$host" 2>&1 ;;
    esac
}

# get_listening_ports
#   Returns: prints "proto|local_addr|process" lines
get_listening_ports() {
    case "$OS" in
        linux)
            ss -tlnpu 2>/dev/null | awk 'NR>1 {
                proto=$1; addr=$4; proc=$NF
                gsub(/users:\(\("|"\)\)/, "", proc)
                printf "%s|%s|%s\n", proto, addr, proc
            }'
            ;;
        macos|bsd)
            if has lsof; then
                lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {printf "tcp|%s|%s\n", $9, $1}'
                lsof -nP -iUDP 2>/dev/null | awk 'NR>1 {printf "udp|%s|%s\n", $9, $1}'
            else
                netstat -an -p tcp 2>/dev/null | awk '/LISTEN/ {printf "tcp|%s|?\n", $4}'
                netstat -an -p udp 2>/dev/null | awk 'NR>2 {printf "udp|%s|?\n", $4}'
            fi
            ;;
        *) echo "unsupported OS" ;;
    esac
}

# get_established_connections
#   Returns: prints "proto|local|remote|process" lines
get_established_connections() {
    case "$OS" in
        linux)
            ss -tupn state established 2>/dev/null | awk 'NR>1 {printf "%s|%s|%s|%s\n", $1, $5, $6, $NF}'
            ;;
        macos|bsd)
            if has lsof; then
                lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | awk 'NR>1 {printf "tcp|%s|%s\n", $9, $1}'
            else
                netstat -an -p tcp 2>/dev/null | awk '/ESTABLISHED/ {printf "tcp|%s|%s|?\n", $4, $5}'
            fi
            ;;
        *) echo "unsupported OS" ;;
    esac
}

# get_dns_servers
#   Returns: prints configured DNS server IPs, one per line
get_dns_servers() {
    if [[ -r /etc/resolv.conf ]]; then
        grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}'
        return 0
    fi
    if [[ "$OS" == "macos" ]] && has scutil; then
        scutil --dns 2>/dev/null | awk '/nameserver\[[0-9]+\]/ {print $3}' | sort -u
    fi
}

# get_local_subnet
#   Returns: prints the local subnet in CIDR notation (best-effort)
get_local_subnet() {
    case "$OS" in
        linux)
            ip -4 route show 2>/dev/null | awk '/proto kernel/ && !/default/ {print $1; exit}'
            ;;
        macos|bsd)
            local iface="" ip=""
            iface=$(get_default_iface)
            [[ -z "$iface" ]] && return 1
            ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2; exit}')
            [[ -z "$ip" ]] && return 1
            echo "${ip%.*}.0/24"
            ;;
        *) return 1 ;;
    esac
}

# get_connection_summary
#   Returns: prints a short socket-summary block (best-effort per platform)
get_connection_summary() {
    case "$OS" in
        linux)     ss -s 2>/dev/null ;;
        macos|bsd) netstat -m 2>/dev/null | head -5 ;;
        *)         echo "unsupported OS" ;;
    esac
}
