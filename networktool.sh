#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════╗
# ║         Network Tool Pro — Daily Use Suite           ║
# ║         By @lexlucas | Version 4.0                   ║
# ╚══════════════════════════════════════════════════════╝
# Cross-platform (Linux / macOS / BSD) network diagnostics suite.
# Interfaces · DNS · Scanning · Web · Monitoring · Speed
#
# Usage:
#   ./networktool.sh                    Interactive menu (TUI)
#   ./networktool.sh --help             CLI usage & examples
#   ./networktool.sh --ping 8.8.8.8     Headless / scriptable mode
#
# Design note on `set` options: this script intentionally does NOT use
# `set -e`. With this much command substitution (`x=$(grep ... )`,
# `x=$(dig ...)`, etc.) a normal "no match" result (grep/dig exit 1) is
# frequent and expected, not an error — `set -e` would abort the whole
# script on those. Every call site that matters checks its own exit status
# explicitly instead. `set -u` (nounset) and `set -o pipefail` are kept:
# every global they can touch is initialized before use.
set -uo pipefail

# ─── Locate ourselves ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
VERSION="4.0"
AUTHOR="@lexlucas"

# ─── Hardcoded fallback defaults (overridable by config file, then CLI) ───────
DEFAULT_PING_COUNT=4
DEFAULT_PORTS="1-1000"
DEFAULT_TIMEOUT=10
COLOR_ENABLED=1
COLORBLIND_SAFE=0
PREFERRED_DNS=""
MAX_LOG_LINES=1000
MAX_LOG_SIZE=5242880   # 5 MB
SPEEDTEST_ENDPOINTS=(
    "https://speed.hetzner.de/10MB.bin"
    "https://ash-speed.hetzner.com/10MB.bin"
    "https://bouygues.testdebit.info/10M.iso"
    "https://nbg1-speed.hetzner.com/10MB.bin"
)

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/networktool/config.ini"
HISTORY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/networktool/history"
LOG_FILE="$SCRIPT_DIR/networktool.log"
RESULTS_FILE="$SCRIPT_DIR/last_result.txt"
TEMP_DIR=""          # set by setup() via mktemp -d
LAST_OUTPUT=""
EXIT_REASON="normal"

# ─── Source modules ────────────────────────────────────────────────────────────
# shellcheck source=lib/utils.sh
source "$LIB_DIR/utils.sh"
# shellcheck source=lib/cli.sh
source "$LIB_DIR/cli.sh"
# shellcheck source=lib/ui.sh
source "$LIB_DIR/ui.sh"
# shellcheck source=lib/platform.sh
source "$LIB_DIR/platform.sh"
# shellcheck source=lib/output.sh
source "$LIB_DIR/output.sh"
# shellcheck source=lib/network.sh
source "$LIB_DIR/network.sh"
# shellcheck source=lib/dns.sh
source "$LIB_DIR/dns.sh"
# shellcheck source=lib/scan.sh
source "$LIB_DIR/scan.sh"
# shellcheck source=lib/web.sh
source "$LIB_DIR/web.sh"
# shellcheck source=lib/monitor.sh
source "$LIB_DIR/monitor.sh"

# ─── Setup / Cleanup ────────────────────────────────────────────────────────────
# setup
#   Args: none
#   Returns: 0
#   Side effects: creates a private temp dir via mktemp -d, ensures the log/
#   history/config directories exist, writes a default config if absent,
#   installs EXIT/INT/TERM traps.
setup() {
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nettool.XXXXXX" 2>/dev/null)" || TEMP_DIR="${TMPDIR:-/tmp}/nettool_$$"
    mkdir -p "$TEMP_DIR" 2>/dev/null
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
    mkdir -p "$(dirname "$HISTORY_FILE")" 2>/dev/null
    write_default_config
    trap _cleanup EXIT
    trap _int_handler INT TERM
}

_cleanup() {
    [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    [[ "$EXIT_REASON" != "normal" && "$OUTPUT_MODE" != "json" ]] && echo -e "\n${GRAY}[cleanup] Temporary files removed.${NC}"
}

_int_handler() {
    EXIT_REASON="interrupt"
    [[ "$OUTPUT_MODE" != "json" ]] && echo -e "\n${YELLOW}Interrupted.${NC}"
    exit 130
}

# ─── Interactive Main Loop ──────────────────────────────────────────────────────
interactive_main() {
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
            help|Help|HELP) show_help ;;
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

# ─── Entry Point ────────────────────────────────────────────────────────────────
main() {
    detect_os
    parse_cli_args "$@"
    load_config
    init_colors
    setup
    log "=== Network Tool Pro v$VERSION started (OS=$OS, mode=$([[ $NONINTERACTIVE -eq 1 ]] && echo cli || echo interactive)) ==="

    if [[ "$NONINTERACTIVE" -eq 1 || -n "$CLI_ACTION" ]]; then
        dispatch_cli
        exit $?
    fi

    interactive_main
}

main "$@"
