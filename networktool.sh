#!/bin/bash
# ╔══════════════════════════════════════════════════════╗
# ║         Network Tool Pro — Daily Use Suite           ║
# ║         By @lexlucas | Version 3.0                   ║
# ╚══════════════════════════════════════════════════════╝
# Comprehensive network diagnostics for everyday use.
# Interfaces · DNS · Scanning · Web · Monitoring · Speed

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/networktool.log"
RESULTS_FILE="$SCRIPT_DIR/last_result.txt"
TEMP_DIR="/tmp/nettool_$$"
VERSION="3.0"
AUTHOR="@lexlucas"

DEFAULT_PING_COUNT=4
DEFAULT_PORTS="1-1000"
DEFAULT_TIMEOUT=10

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Setup ────────────────────────────────────────────────────────────────────
EXIT_REASON="normal"
LAST_OUTPUT=""

setup() {
    mkdir -p "$TEMP_DIR"
    touch "$LOG_FILE"
    trap _cleanup EXIT
    trap '_int_handler' INT TERM
}

_cleanup() {
    rm -rf "$TEMP_DIR"
    [[ "$EXIT_REASON" != "normal" ]] && echo -e "\n${GRAY}[cleanup] Temporary files removed.${NC}"
}

_int_handler() {
    EXIT_REASON="interrupt"
    echo -e "\n${YELLOW}Interrupted.${NC}"
    exit 130
}

# ─── Utilities ────────────────────────────────────────────────────────────────
log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" >> "$LOG_FILE"
}

info()    { echo -e "${CYAN}[*]${NC} $*"; }
ok()      { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
err()     { echo -e "${RED}[-]${NC} $*" >&2; }

section() {
    echo -e "\n${BOLD}${BLUE}── $* ──────────────────────────────────────────${NC}"
}

divider() {
    echo -e "${GRAY}────────────────────────────────────────────────────${NC}"
}

has() { command -v "$1" >/dev/null 2>&1; }

need() {
    local missing=()
    for t in "$@"; do has "$t" || missing+=("$t"); done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing: ${missing[*]}"
        warn "Install with: sudo apt install ${missing[*]}"
        return 1
    fi
}

prompt() {
    local var default label
    label="$1"; default="$2"
    read -rp "$(echo -e "${CYAN}?${NC} ${label} [${GRAY}${default}${NC}]: ")" var
    echo "${var:-$default}"
}

pause() {
    echo
    read -rp "$(echo -e "${GRAY}  Press Enter to continue...${NC}")"
}

save_result() {
    echo "$LAST_OUTPUT" > "$RESULTS_FILE"
    ok "Result saved to: $RESULTS_FILE"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║        Network Tool Pro  v${VERSION}  ${AUTHOR}        ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ─── Main Menu ────────────────────────────────────────────────────────────────
menu() {
    banner
    echo -e "  ${BOLD}QUICK${NC}"
    echo -e "  ${WHITE}1)${NC}  Dashboard          ${GRAY}(IP, interfaces, GW, DNS at a glance)${NC}"
    echo
    echo -e "  ${BOLD}NETWORK${NC}"
    echo -e "  ${WHITE}2)${NC}  Interface Info     ${GRAY}(IPs, MAC, state, stats)${NC}"
    echo -e "  ${WHITE}3)${NC}  Routing Table      ${GRAY}(routes, gateway, ARP)${NC}"
    echo -e "  ${WHITE}4)${NC}  Local Discovery    ${GRAY}(scan hosts on LAN)${NC}"
    echo
    echo -e "  ${BOLD}CONNECTIVITY${NC}"
    echo -e "  ${WHITE}5)${NC}  Ping               ${GRAY}(test reachability)${NC}"
    echo -e "  ${WHITE}6)${NC}  Traceroute         ${GRAY}(hop-by-hop path)${NC}"
    echo -e "  ${WHITE}7)${NC}  MTU Discovery      ${GRAY}(find max packet size)${NC}"
    echo
    echo -e "  ${BOLD}DNS${NC}"
    echo -e "  ${WHITE}8)${NC}  DNS Lookup         ${GRAY}(A, AAAA, MX, NS, TXT)${NC}"
    echo -e "  ${WHITE}9)${NC}  Reverse DNS        ${GRAY}(IP → hostname)${NC}"
    echo -e "  ${WHITE}10)${NC} Whois              ${GRAY}(domain / IP registration)${NC}"
    echo
    echo -e "  ${BOLD}SCANNING${NC}"
    echo -e "  ${WHITE}11)${NC} Port Scan          ${GRAY}(nmap, open ports)${NC}"
    echo -e "  ${WHITE}12)${NC} Service Scan       ${GRAY}(versions + OS detect)${NC}"
    echo -e "  ${WHITE}13)${NC} Vuln Check         ${GRAY}(nmap scripting engine)${NC}"
    echo
    echo -e "  ${BOLD}WEB & TLS${NC}"
    echo -e "  ${WHITE}14)${NC} HTTP Check         ${GRAY}(headers, status code, redirect)${NC}"
    echo -e "  ${WHITE}15)${NC} SSL Certificate    ${GRAY}(expiry, issuer, SANs)${NC}"
    echo -e "  ${WHITE}16)${NC} IP Geolocation     ${GRAY}(country, ASN, org)${NC}"
    echo
    echo -e "  ${BOLD}MONITORING${NC}"
    echo -e "  ${WHITE}17)${NC} Active Connections ${GRAY}(established sessions)${NC}"
    echo -e "  ${WHITE}18)${NC} Listening Ports    ${GRAY}(services waiting for connections)${NC}"
    echo -e "  ${WHITE}19)${NC} Speed Test         ${GRAY}(download bandwidth)${NC}"
    echo -e "  ${WHITE}20)${NC} Live Bandwidth     ${GRAY}(real-time interface stats)${NC}"
    echo
    echo -e "  ${BOLD}TOOLS${NC}"
    echo -e "  ${WHITE}21)${NC} View Log           ${GRAY}(last 30 entries)${NC}"
    echo -e "  ${WHITE}22)${NC} Export Last Result ${GRAY}(save to file)${NC}"
    echo -e "  ${WHITE}0)${NC}  Exit"
    echo
    echo -ne "  ${BOLD}Choice${NC} (0-22): "
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. DASHBOARD
# ═════════════════════════════════════════════════════════════════════════════
dashboard() {
    log "Dashboard"
    banner
    section "Public IP"
    local pub_ip
    pub_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
          || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
          || echo "unavailable")
    ok "Public IP : ${BOLD}$pub_ip${NC}"

    section "Primary Interface"
    local iface gw
    iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -1)
    local local_ip
    local_ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | head -1)
    ok "Interface  : ${BOLD}$iface${NC}"
    ok "Local IP   : ${BOLD}$local_ip${NC}"
    ok "Gateway    : ${BOLD}$gw${NC}"

    section "DNS Servers"
    grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print "  "$2}' \
        || echo "  /etc/resolv.conf not found"

    section "Connectivity"
    local targets=(8.8.8.8 1.1.1.1 google.com)
    for t in "${targets[@]}"; do
        if ping -c1 -W2 "$t" >/dev/null 2>&1; then
            ok "  $t  ${GREEN}REACHABLE${NC}"
        else
            err "  $t  ${RED}UNREACHABLE${NC}"
        fi
    done

    section "Open Listening Ports (top 10)"
    ss -tlnp 2>/dev/null | awk 'NR>1 {printf "  %-8s %-24s %s\n", $1, $4, $NF}' | head -10

    LAST_OUTPUT="Dashboard snapshot $(date)"
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. INTERFACE INFO
# ═════════════════════════════════════════════════════════════════════════════
interface_info() {
    log "Interface info"
    section "Network Interfaces"
    ip addr show | awk '
        /^[0-9]+:/ {
            split($0, a, ": "); iface=a[2]
            gsub(/@.*/, "", iface)
        }
        /state (UP|DOWN|UNKNOWN)/ {
            match($0, /state [A-Z]+/, m); state=m[0]
        }
        /link\/ether/ { mac=$2 }
        /inet / {
            printf "\033[1;33m%-14s\033[0m %-8s %-20s MAC: %s\n", iface, state, $2, mac
        }
    '

    section "Interface Statistics"
    ip -s link | awk '
        /^[0-9]+:/ {
            split($0, a, ": "); iface=a[2]; gsub(/@.*/, "", iface)
            rx_line=0; tx_line=0
        }
        /RX:/ { rx_line=NR+1 }
        /TX:/ { tx_line=NR+1 }
        NR==rx_line { rx=$1 }
        NR==tx_line { tx=$1; printf "  %-16s RX: %-14s TX: %s bytes\n", iface, rx, tx }
    '
    LAST_OUTPUT=$(ip addr show)
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. ROUTING TABLE
# ═════════════════════════════════════════════════════════════════════════════
routing_table() {
    log "Routing table"
    section "Default Gateway"
    ip route show default

    section "Full Routing Table"
    ip route show | column -t

    section "ARP / Neighbour Table"
    ip neigh show | sort -k3

    LAST_OUTPUT=$(ip route show; echo; ip neigh show)
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. LOCAL DISCOVERY
# ═════════════════════════════════════════════════════════════════════════════
local_discovery() {
    log "Local discovery"
    if ! need nmap; then return; fi

    local subnet
    subnet=$(ip -4 route show | awk '/src/ && !/default/ {print $1}' | head -1)
    subnet=$(prompt "Subnet to scan" "${subnet:-192.168.1.0/24}")

    info "Scanning $subnet (ping sweep + ARP)..."
    section "Live Hosts"
    nmap -sn "$subnet" 2>/dev/null | awk '
        /Nmap scan report/ { ip=$NF }
        /MAC Address/      { printf "  %-18s %s\n", ip, $0 }
        /Host is up/ && !found[ip]++ && !/MAC/ { printf "  %-18s (no MAC — local host)\n", ip }
    '
    LAST_OUTPUT=$(nmap -sn "$subnet" 2>/dev/null)
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. PING
# ═════════════════════════════════════════════════════════════════════════════
ping_host() {
    local host count
    host=$(prompt "Host to ping" "8.8.8.8")
    count=$(prompt "Packet count" "$DEFAULT_PING_COUNT")

    log "Ping $host x$count"
    section "Ping → $host"

    if ping -c "$count" -i 0.2 -W 2 "$host"; then
        ok "Ping succeeded."
    else
        err "Ping failed or host unreachable."
    fi
    LAST_OUTPUT=$(ping -c "$count" -i 0.2 -W 2 "$host" 2>&1 || true)
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. TRACEROUTE
# ═════════════════════════════════════════════════════════════════════════════
trace_route() {
    local host
    host=$(prompt "Target host" "8.8.8.8")
    log "Traceroute → $host"
    section "Traceroute → $host"

    if has traceroute; then
        traceroute -m 30 -w 1 -q 1 "$host" 2>/dev/null
    elif has tracepath; then
        tracepath "$host" 2>/dev/null
    else
        err "Neither traceroute nor tracepath found."
        warn "Install: sudo apt install traceroute"
        return 1
    fi
    LAST_OUTPUT=$(traceroute -m 30 -w 1 -q 1 "$host" 2>&1 || true)
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. MTU DISCOVERY
# ═════════════════════════════════════════════════════════════════════════════
mtu_discovery() {
    local host
    host=$(prompt "Target host" "8.8.8.8")
    log "MTU discovery → $host"
    section "MTU Discovery → $host"

    info "Probing MTU sizes (this may take ~30 seconds)..."
    local mtu found=0
    for mtu in 1500 1492 1480 1454 1400 1300 1200 576; do
        local result
        result=$(ping -M do -s "$((mtu-28))" -c1 -W2 "$host" 2>&1 || true)
        if echo "$result" | grep -q '1 received'; then
            ok "MTU ${BOLD}${mtu}${NC} bytes — ${GREEN}OK${NC}"
            found=$mtu
            break
        else
            warn "MTU $mtu — too large"
        fi
    done

    [[ $found -gt 0 ]] && ok "Effective MTU: ${BOLD}${found}${NC}" || err "Could not determine MTU."
    LAST_OUTPUT="MTU discovery to $host: $found"
}

# ═════════════════════════════════════════════════════════════════════════════
# 8. DNS LOOKUP
# ═════════════════════════════════════════════════════════════════════════════
dns_lookup() {
    local domain
    domain=$(prompt "Domain to resolve" "google.com")
    log "DNS lookup → $domain"
    section "DNS Lookup → $domain"

    if has dig; then
        for rtype in A AAAA MX NS TXT; do
            local result
            result=$(dig +short "$rtype" "$domain" 2>/dev/null)
            if [[ -n "$result" ]]; then
                echo -e "  ${BOLD}${rtype}${NC}:"
                echo "$result" | sed 's/^/    /'
            fi
        done

        section "DNS Query Stats"
        dig "$domain" 2>/dev/null | awk '/^;; (Query|SERVER|WHEN|MSG SIZE)/ {print "  "$0}'

    elif has nslookup; then
        nslookup "$domain"
    elif has host; then
        host -a "$domain"
    else
        err "No DNS tool available (dig/nslookup/host)."
        return 1
    fi

    section "Configured DNS Servers"
    grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print "  "$2}'

    LAST_OUTPUT=$(dig "$domain" 2>/dev/null || nslookup "$domain" 2>/dev/null || true)
}

# ═════════════════════════════════════════════════════════════════════════════
# 9. REVERSE DNS
# ═════════════════════════════════════════════════════════════════════════════
reverse_dns() {
    local ip
    ip=$(prompt "IP address" "8.8.8.8")
    log "Reverse DNS → $ip"
    section "Reverse DNS → $ip"

    if has dig; then
        local result
        result=$(dig +short -x "$ip" 2>/dev/null)
        [[ -n "$result" ]] && ok "Hostname: ${BOLD}$result${NC}" || warn "No PTR record found."
    elif has host; then
        host "$ip"
    else
        err "No DNS tool found."
    fi
    LAST_OUTPUT="Reverse DNS $ip: $(dig +short -x "$ip" 2>/dev/null || true)"
}

# ═════════════════════════════════════════════════════════════════════════════
# 10. WHOIS
# ═════════════════════════════════════════════════════════════════════════════
whois_lookup() {
    local target
    target=$(prompt "Domain or IP" "google.com")
    log "Whois → $target"
    section "Whois → $target"

    if has whois; then
        whois "$target" 2>/dev/null | grep -Ei \
            '(registrar|registrant|organization|country|creation|expir|updated|name.server|netname|inetnum|route|aut-num|descr|abuse)' \
            | head -40
        ok "Full result available via: whois $target"
    else
        info "Using online RDAP fallback..."
        if has curl; then
            local encoded="${target//./DOT}"
            curl -s "https://rdap.org/domain/$target" 2>/dev/null \
                | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'  {k}: {v}') for k,v in d.items() if isinstance(v,str)]" 2>/dev/null \
                || err "RDAP lookup failed. Install whois: sudo apt install whois"
        else
            err "Neither whois nor curl available."
        fi
    fi
    LAST_OUTPUT="Whois $target"
}

# ═════════════════════════════════════════════════════════════════════════════
# 11. PORT SCAN
# ═════════════════════════════════════════════════════════════════════════════
port_scan() {
    if ! need nmap; then return; fi

    local host ports
    host=$(prompt "Target host" "localhost")
    ports=$(prompt "Port range" "$DEFAULT_PORTS")
    log "Port scan → $host:$ports"
    section "Port Scan → $host ($ports)"

    local scan_flag="-sT"
    if [[ $EUID -eq 0 ]]; then
        scan_flag="-sS"
        info "Running SYN scan (root)."
    else
        info "Running TCP connect scan (non-root)."
    fi

    nmap "$scan_flag" -p "$ports" --open -T4 --max-retries 2 --host-timeout 60s "$host" 2>/dev/null
    LAST_OUTPUT=$(nmap "$scan_flag" -p "$ports" --open -T4 --max-retries 2 --host-timeout 60s "$host" 2>/dev/null)
}

# ═════════════════════════════════════════════════════════════════════════════
# 12. SERVICE VERSION SCAN
# ═════════════════════════════════════════════════════════════════════════════
service_scan() {
    if ! need nmap; then return; fi

    local host ports
    host=$(prompt "Target host" "localhost")
    ports=$(prompt "Port range" "1-1000")
    log "Service scan → $host:$ports"
    section "Service Version Scan → $host"

    if [[ $EUID -ne 0 ]]; then
        warn "Root recommended for accurate OS detection."
    fi

    nmap -sV -O --open -p "$ports" -T4 --max-retries 1 --host-timeout 120s "$host" 2>/dev/null \
        || nmap -sV --open -p "$ports" -T4 "$host" 2>/dev/null
    LAST_OUTPUT="Service scan on $host"
}

# ═════════════════════════════════════════════════════════════════════════════
# 13. VULNERABILITY CHECK (NSE)
# ═════════════════════════════════════════════════════════════════════════════
vuln_check() {
    if ! need nmap; then return; fi

    warn "Only scan systems you own or have written permission to test."
    echo -ne "  ${YELLOW}Continue? [y/N]:${NC} "; read -r yn
    [[ "$yn" =~ ^[Yy]$ ]] || return

    local host ports
    host=$(prompt "Target host" "localhost")
    ports=$(prompt "Ports to check" "22,80,443,8080,3389")
    log "Vuln check → $host:$ports"
    section "Vulnerability Check → $host"

    nmap -sV --script=vuln,auth,default -p "$ports" \
        --script-timeout 30s --host-timeout 120s "$host" 2>/dev/null \
        | grep -v "^|  $" | head -80
    LAST_OUTPUT="Vuln check on $host"
}

# ═════════════════════════════════════════════════════════════════════════════
# 14. HTTP CHECK
# ═════════════════════════════════════════════════════════════════════════════
http_check() {
    if ! need curl; then return; fi

    local url
    url=$(prompt "URL" "https://example.com")
    [[ "$url" != http* ]] && url="https://$url"
    log "HTTP check → $url"
    section "HTTP Check → $url"

    info "Sending request..."
    local out
    out=$(curl -siL --max-time 15 \
        -A "NetworkTool/$VERSION" \
        -w "\n\n--- CURL STATS ---\nHTTP Code: %{http_code}\nTotal Time: %{time_total}s\nRedirect URL: %{url_effective}\nSize: %{size_download} bytes\nSpeed: %{speed_download} bytes/s\n" \
        "$url" 2>/dev/null)

    echo "$out" | awk '
        /^HTTP\// { print "\033[1;33m" $0 "\033[0m"; next }
        /^(Date|Server|Content-Type|Location|X-Frame|Strict-Transport|X-Content-Type|Content-Security|Cache-Control):/ { print "  \033[0;36m" $0 "\033[0m"; next }
        /^--- CURL STATS ---/ { print "\n\033[1;34m" $0 "\033[0m"; next }
        /^(HTTP Code|Total Time|Redirect|Size|Speed):/ { print "  \033[0;32m" $0 "\033[0m"; next }
    '
    LAST_OUTPUT="$out"
}

# ═════════════════════════════════════════════════════════════════════════════
# 15. SSL CERTIFICATE
# ═════════════════════════════════════════════════════════════════════════════
ssl_cert() {
    if ! need openssl; then return; fi

    local host port
    host=$(prompt "Hostname" "google.com")
    port=$(prompt "Port" "443")
    log "SSL check → $host:$port"
    section "SSL Certificate → $host:$port"

    local raw
    raw=$(echo | timeout "$DEFAULT_TIMEOUT" openssl s_client \
        -connect "${host}:${port}" \
        -servername "$host" 2>/dev/null \
        | openssl x509 -noout -text 2>/dev/null)

    if [[ -z "$raw" ]]; then
        err "Could not retrieve certificate."
        return 1
    fi

    local subject issuer not_before not_after sans
    subject=$(echo "$raw" | grep 'Subject:' | head -1 | sed 's/.*Subject: //')
    issuer=$(echo "$raw" | grep 'Issuer:' | head -1 | sed 's/.*Issuer: //')
    not_before=$(echo "$raw" | grep 'Not Before' | sed 's/.*Not Before: //')
    not_after=$(echo "$raw" | grep 'Not After' | sed 's/.*Not After : //')
    sans=$(echo "$raw" | grep -A1 'Subject Alternative Name' | tail -1 | tr ',' '\n' | grep DNS | sed 's/.*DNS:/  /' | head -10)

    ok "Subject   : $subject"
    ok "Issuer    : $issuer"
    ok "Valid From: $not_before"

    # Check expiry
    local exp_epoch now_epoch days_left
    exp_epoch=$(date -d "$not_after" +%s 2>/dev/null \
             || date -j -f "%b %d %T %Y %Z" "$not_after" +%s 2>/dev/null \
             || echo 0)
    now_epoch=$(date +%s)
    days_left=$(( (exp_epoch - now_epoch) / 86400 ))

    if [[ $days_left -lt 0 ]]; then
        err "Expiry    : $not_after  ${RED}EXPIRED${NC}"
    elif [[ $days_left -lt 30 ]]; then
        warn "Expiry    : $not_after  ${YELLOW}(expires in ${days_left} days)${NC}"
    else
        ok "Expiry    : $not_after  ${GREEN}($days_left days remaining)${NC}"
    fi

    echo -e "\n${BOLD}SANs:${NC}"
    echo "$sans"

    # Cipher info
    section "Cipher Suite"
    echo | timeout "$DEFAULT_TIMEOUT" openssl s_client \
        -connect "${host}:${port}" -servername "$host" 2>/dev/null \
        | grep -E '(Cipher|Protocol|Verify)' | head -5

    LAST_OUTPUT="SSL check $host:$port — $days_left days left"
}

# ═════════════════════════════════════════════════════════════════════════════
# 16. IP GEOLOCATION
# ═════════════════════════════════════════════════════════════════════════════
geolocate() {
    if ! need curl; then return; fi

    local ip
    ip=$(prompt "IP address (blank = your public IP)" "")
    [[ -z "$ip" ]] && ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
    log "Geolocation → $ip"
    section "IP Geolocation → $ip"

    local data
    data=$(curl -s --max-time 10 "https://ipinfo.io/${ip}/json" 2>/dev/null)

    if [[ -n "$data" ]]; then
        echo "$data" | python3 -c "
import sys, json
d = json.load(sys.stdin)
fields = ['ip','city','region','country','org','postal','timezone','loc']
for f in fields:
    if f in d:
        print(f'  {f:<12}: {d[f]}')
" 2>/dev/null || echo "$data" | grep -Eo '"[^"]+":"[^"]+"' | sed 's/"//g; s/:/: /' | head -15
    else
        err "Geolocation lookup failed."
    fi
    LAST_OUTPUT="Geolocation: $ip → $data"
}

# ═════════════════════════════════════════════════════════════════════════════
# 17. ACTIVE CONNECTIONS
# ═════════════════════════════════════════════════════════════════════════════
active_connections() {
    log "Active connections"
    section "Established Connections"

    ss -tupn state established 2>/dev/null \
        | awk 'NR==1{print; next} {printf "  %-6s %-25s %-25s %s\n", $1, $5, $6, $NF}' \
        | head -30

    section "Connection Summary"
    ss -s 2>/dev/null | head -10

    LAST_OUTPUT=$(ss -tupn state established 2>/dev/null)
}

# ═════════════════════════════════════════════════════════════════════════════
# 18. LISTENING PORTS
# ═════════════════════════════════════════════════════════════════════════════
listening_ports() {
    log "Listening ports"
    section "Listening Ports (TCP + UDP)"

    printf "  ${BOLD}%-8s %-30s %s${NC}\n" "Proto" "Address:Port" "Process"
    divider
    ss -tlnpu 2>/dev/null | awk 'NR>1 {
        proto=$1; addr=$4; proc=$NF
        gsub(/users:\(\("|"\)\)/, "", proc)
        printf "  %-8s %-30s %s\n", proto, addr, proc
    }' | sort -k2

    LAST_OUTPUT=$(ss -tlnpu 2>/dev/null)
}

# ═════════════════════════════════════════════════════════════════════════════
# 19. SPEED TEST
# ═════════════════════════════════════════════════════════════════════════════
speed_test() {
    if ! need curl; then return; fi

    log "Speed test"
    section "Download Speed Test"

    local endpoints=(
        "https://speed.hetzner.de/10MB.bin"
        "https://ash-speed.hetzner.com/10MB.bin"
        "https://bouygues.testdebit.info/10M.iso"
        "https://nbg1-speed.hetzner.com/10MB.bin"
    )

    local success=false
    for url in "${endpoints[@]}"; do
        info "Testing: $url"
        local speed mbps
        speed=$(curl -o /dev/null -w "%{speed_download}" \
            -s --max-time 25 "$url" 2>/dev/null)

        if [[ -n "$speed" && "$speed" != "0" ]] && awk "BEGIN {exit ($speed < 100)}"; then
            mbps=$(awk "BEGIN {printf \"%.2f\", $speed * 8 / 1000000}")
            ok "${BOLD}${mbps} Mbps${NC}  (${speed} bytes/s)"
            success=true
            LAST_OUTPUT="Speed test: $mbps Mbps"
            break
        else
            warn "Endpoint unreachable."
        fi
    done

    $success || err "All speed test endpoints failed."
}

# ═════════════════════════════════════════════════════════════════════════════
# 20. LIVE BANDWIDTH
# ═════════════════════════════════════════════════════════════════════════════
live_bandwidth() {
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    iface=$(prompt "Interface to monitor" "${iface:-eth0}")
    local interval
    interval=$(prompt "Refresh interval (seconds)" "2")

    if [[ ! -f "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
        err "Interface $iface not found."
        return 1
    fi

    info "Monitoring $iface — press Ctrl+C to stop."
    echo
    printf "  ${BOLD}%-12s %-20s %-20s %-15s %-15s${NC}\n" \
        "Time" "RX (bytes/s)" "TX (bytes/s)" "RX (Kbps)" "TX (Kbps)"
    divider

    local prev_rx prev_tx
    prev_rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
    prev_tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes")

    while true; do
        sleep "$interval"
        local cur_rx cur_tx ts
        cur_rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes")
        cur_tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes")
        ts=$(date '+%H:%M:%S')

        local rx_rate tx_rate rx_kbps tx_kbps
        rx_rate=$(( (cur_rx - prev_rx) / interval ))
        tx_rate=$(( (cur_tx - prev_tx) / interval ))
        rx_kbps=$(awk "BEGIN {printf \"%.1f\", $rx_rate * 8 / 1000}")
        tx_kbps=$(awk "BEGIN {printf \"%.1f\", $tx_rate * 8 / 1000}")

        printf "  %-12s %-20s %-20s %-15s %-15s\n" \
            "$ts" "$rx_rate" "$tx_rate" "$rx_kbps" "$tx_kbps"

        prev_rx=$cur_rx
        prev_tx=$cur_tx
    done
}

# ═════════════════════════════════════════════════════════════════════════════
# 21. VIEW LOG
# ═════════════════════════════════════════════════════════════════════════════
view_log() {
    section "Last 30 Log Entries — $LOG_FILE"
    if [[ -f "$LOG_FILE" ]]; then
        tail -30 "$LOG_FILE"
    else
        warn "No log file found yet."
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# 22. EXPORT RESULT
# ═════════════════════════════════════════════════════════════════════════════
export_result() {
    if [[ -z "$LAST_OUTPUT" ]]; then
        warn "No result to export. Run a diagnostic first."
        return
    fi
    save_result
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN LOOP
# ═════════════════════════════════════════════════════════════════════════════
main() {
    setup
    log "=== Network Tool Pro v$VERSION started ==="

    while true; do
        menu
        read -r choice

        case "$choice" in
            1)  dashboard ;;
            2)  interface_info ;;
            3)  routing_table ;;
            4)  local_discovery ;;
            5)  ping_host ;;
            6)  trace_route ;;
            7)  mtu_discovery ;;
            8)  dns_lookup ;;
            9)  reverse_dns ;;
            10) whois_lookup ;;
            11) port_scan ;;
            12) service_scan ;;
            13) vuln_check ;;
            14) http_check ;;
            15) ssl_cert ;;
            16) geolocate ;;
            17) active_connections ;;
            18) listening_ports ;;
            19) speed_test ;;
            20) live_bandwidth ;;
            21) view_log ;;
            22) export_result ;;
            0)
                log "=== Tool exited normally ==="
                echo -e "\n${GREEN}Goodbye, $AUTHOR.${NC}\n"
                EXIT_REASON="normal"
                exit 0
                ;;
            *)
                err "Invalid choice: '$choice'"
                ;;
        esac

        pause
    done
}

main
