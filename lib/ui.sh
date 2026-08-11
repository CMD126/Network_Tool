#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/ui.sh — Colors, symbols, banner, menu, prompts (with history), status
#             bar, help text. All human-facing presentation lives here.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# ─── Colors ───────────────────────────────────────────────────────────────────
# init_colors
#   Args: none
#   Returns: 0
#   Side effects: sets color escape-code globals. If COLOR_ENABLED=0 or stdout
#   is not a terminal, all colors become empty strings (safe for pipes/logs).
init_colors() {
    if [[ "${COLOR_ENABLED:-1}" -eq 1 && -t 1 ]]; then
        RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
        WHITE='\033[1;37m'; GRAY='\033[0;37m'; BOLD='\033[1m'; NC='\033[0m'
    else
        RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''
        WHITE=''; GRAY=''; BOLD=''; NC=''
    fi
}

# ─── Colorblind-safe symbols ───────────────────────────────────────────────────
# Symbols are always shown alongside color so meaning doesn't depend on hue.
SYM_OK='+'
SYM_WARN='!'
SYM_ERR='-'
SYM_INFO='*'

# ─── Output primitives ─────────────────────────────────────────────────────────
# These are the ONLY functions feature code should call to talk to the user.
# They respect $OUTPUT_MODE (human|json) and $QUIET so a single code path
# works interactively and headlessly:
#   - json mode:  all human chatter is suppressed (only json_output prints)
#   - quiet mode: info/section/divider/banner suppressed, results still shown

info() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    [[ "$QUIET" -eq 1 ]] && return 0
    echo -e "${CYAN}[${SYM_INFO}]${NC} $*"
}

ok() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    echo -e "${GREEN}[${SYM_OK}]${NC} $*"
}

warn() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    echo -e "${YELLOW}[${SYM_WARN}]${NC} $*"
}

err() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    echo -e "${RED}[${SYM_ERR}]${NC} $*" >&2
}

section() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    [[ "$QUIET" -eq 1 ]] && return 0
    echo -e "\n${BOLD}${BLUE}── $* ──────────────────────────────────────────${NC}"
}

divider() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    [[ "$QUIET" -eq 1 ]] && return 0
    echo -e "${GRAY}────────────────────────────────────────────────────${NC}"
}

# ─── Prompts (with history) ────────────────────────────────────────────────────
# prompt <label> <default>
#   Args: $1 = prompt label, $2 = default value if user hits Enter
#   Returns: prints the (sanitized) chosen value on stdout
#   Side effects: remembers non-empty values in the target history file
prompt() {
    local var="" default="" label=""
    label="$1"; default="$2"
    read -rp "$(echo -e "${CYAN}?${NC} ${label} [${GRAY}${default}${NC}] ${GRAY}(type 'h' for history)${NC}: ")" var
    if [[ "$var" == "h" || "$var" == "H" ]]; then
        show_history
        read -rp "$(echo -e "${CYAN}?${NC} ${label} [${GRAY}${default}${NC}]: ")" var
    fi
    var="${var:-$default}"
    var="$(sanitize_input "$var")"
    [[ -n "$var" && "$var" != "$default" ]] && remember_target "$var"
    echo "$var"
}

# show_history
#   Args: none
#   Returns: 0
#   Side effects: prints the last 10 remembered targets to stdout
show_history() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    echo -e "  ${BOLD}Recent targets:${NC}"
    local n=1 t
    while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        echo -e "    ${GRAY}${n})${NC} $t"
        n=$((n + 1))
    done < <(recent_targets)
    [[ $n -eq 1 ]] && echo -e "    ${GRAY}(none yet)${NC}"
}

# pause
#   Args: none
#   Returns: 0
#   Side effects: blocks until the user presses Enter (interactive TUI only)
pause() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    echo
    read -rp "$(echo -e "${GRAY}  Press Enter to continue...${NC}")" _
}

# ─── Banner & Status Bar ───────────────────────────────────────────────────────
banner() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    clear 2>/dev/null || printf '\033c'
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║        Network Tool Pro  v${VERSION}  ${AUTHOR}        ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${GRAY}OS: ${OS}  |  Config: ${CONFIG_FILE}${NC}"
    status_bar
}

# status_bar
#   Args: none
#   Returns: 0
#   Side effects: prints a one-line summary of the most recent result, e.g.
#   "Last result: Ping 8.8.8.8 — 0% loss"
status_bar() {
    [[ "$OUTPUT_MODE" == "json" ]] && return 0
    if [[ ${#RESULT_LABELS[@]} -gt 0 ]]; then
        local last_idx=$(( ${#RESULT_LABELS[@]} - 1 ))
        echo -e "  ${MAGENTA}Last result:${NC} ${RESULT_LABELS[$last_idx]}"
    else
        echo -e "  ${GRAY}Last result: (none yet — run a diagnostic)${NC}"
    fi
}

# ─── Help ──────────────────────────────────────────────────────────────────────
# show_help
#   Args: none
#   Returns: 0
#   Side effects: prints CLI + TUI usage help to stdout
show_help() {
    cat <<EOF
${BOLD}Network Tool Pro v${VERSION}${NC} — cross-platform network diagnostics suite

${BOLD}INTERACTIVE MODE${NC}
  ./networktool.sh
      Launches the menu-driven TUI. Type 'help' at the menu prompt for this
      text, or 'h' at any target prompt to see recent target history.

${BOLD}CLI (NON-INTERACTIVE) MODE${NC}
  ./networktool.sh --dashboard
  ./networktool.sh --ping 8.8.8.8 --count 10
  ./networktool.sh --traceroute example.com
  ./networktool.sh --mtu 8.8.8.8
  ./networktool.sh --dns google.com
  ./networktool.sh --reverse-dns 8.8.8.8
  ./networktool.sh --whois example.com
  ./networktool.sh --port-scan 192.168.1.1 --ports 22,80,443
  ./networktool.sh --service-scan 192.168.1.1 --ports 1-1000
  ./networktool.sh --vuln-check 192.168.1.1 --yes
  ./networktool.sh --http https://example.com --json
  ./networktool.sh --ssl example.com --port 443
  ./networktool.sh --geolocate 8.8.8.8
  ./networktool.sh --interfaces
  ./networktool.sh --routes
  ./networktool.sh --discover 192.168.1.0/24
  ./networktool.sh --connections
  ./networktool.sh --listening
  ./networktool.sh --speed-test --quiet
  ./networktool.sh --live-bandwidth eth0 --samples 5

${BOLD}GLOBAL FLAGS${NC}
  --json          Structured JSON output (one object, pipeable to jq)
  --quiet         Minimal human output (suppress banners/section headers)
  --no-color      Disable ANSI colors
  --count N       Ping packet count (with --ping)
  --ports RANGE   Port range/list (with --port-scan/--service-scan/--vuln-check)
  --port N        Single port (with --ssl)
  --samples N     Sample count (with --live-bandwidth, non-interactive)
  --yes           Skip the confirmation prompt on --vuln-check
  -h, --help      Show this help and exit

${BOLD}CONFIG${NC}
  Config file : ${CONFIG_FILE}
  History file: ${HISTORY_FILE}
  Log file    : ${LOG_FILE}
EOF
}

# ─── Main Menu ──────────────────────────────────────────────────────────────────
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
    echo -e "  ${WHITE}21)${NC} View Log           ${GRAY}(last entries)${NC}"
    echo -e "  ${WHITE}22)${NC} Export Last Result ${GRAY}(save to file, pick by index)${NC}"
    echo -e "  ${WHITE}help)${NC} Help               ${GRAY}(usage & CLI examples)${NC}"
    echo -e "  ${WHITE}0)${NC}  Exit"
    echo
    echo -ne "  ${BOLD}Choice${NC} (0-22): "
}
