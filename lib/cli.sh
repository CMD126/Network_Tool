#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/cli.sh — Non-interactive (headless) argument parsing & dispatch.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

CLI_ACTION=""
CLI_TARGET=""
CLI_COUNT=""
CLI_PORTS=""
CLI_PORT=""
CLI_IFACE=""
CLI_INTERVAL=""
CLI_SAMPLES=""
CLI_INDEX=""
CONFIRM_YES=0
NONINTERACTIVE=0
OUTPUT_MODE="human"
QUIET=0

# parse_cli_args <args...>
#   Args: the script's full argv
#   Returns: 0
#   Side effects: sets CLI_ACTION and the CLI_* value globals, plus the
#   cross-cutting globals NONINTERACTIVE, OUTPUT_MODE, QUIET, COLOR_ENABLED.
#   An unrecognized flag falls back to CLI_ACTION=help.
parse_cli_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)        CLI_ACTION="help" ;;
            --dashboard)      CLI_ACTION="dashboard"; NONINTERACTIVE=1 ;;
            --interfaces)     CLI_ACTION="interface_info"; NONINTERACTIVE=1 ;;
            --routes)         CLI_ACTION="routing_table"; NONINTERACTIVE=1 ;;
            --discover)       CLI_ACTION="local_discovery"; NONINTERACTIVE=1
                               _cli_take_optional_value CLI_TARGET "$@" && shift ;;
            --ping)           CLI_ACTION="ping_host"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --traceroute)     CLI_ACTION="trace_route"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --mtu)            CLI_ACTION="mtu_discovery"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --dns)            CLI_ACTION="dns_lookup"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --reverse-dns)    CLI_ACTION="reverse_dns"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --whois)          CLI_ACTION="whois_lookup"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --port-scan)      CLI_ACTION="port_scan"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --service-scan)   CLI_ACTION="service_scan"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --vuln-check)     CLI_ACTION="vuln_check"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --http)           CLI_ACTION="http_check"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --ssl)            CLI_ACTION="ssl_cert"; NONINTERACTIVE=1; shift; CLI_TARGET="${1:-}" ;;
            --geolocate)      CLI_ACTION="geolocate"; NONINTERACTIVE=1
                               _cli_take_optional_value CLI_TARGET "$@" && shift ;;
            --connections)    CLI_ACTION="active_connections"; NONINTERACTIVE=1 ;;
            --listening)      CLI_ACTION="listening_ports"; NONINTERACTIVE=1 ;;
            --speed-test)     CLI_ACTION="speed_test"; NONINTERACTIVE=1 ;;
            --live-bandwidth) CLI_ACTION="live_bandwidth"; NONINTERACTIVE=1
                               _cli_take_optional_value CLI_IFACE "$@" && shift ;;
            --view-log)       CLI_ACTION="view_log"; NONINTERACTIVE=1 ;;
            --export)         CLI_ACTION="export_result"; NONINTERACTIVE=1
                               _cli_take_optional_value CLI_INDEX "$@" && shift ;;
            --count)          shift; CLI_COUNT="${1:-}" ;;
            --ports)          shift; CLI_PORTS="${1:-}" ;;
            --port)           shift; CLI_PORT="${1:-}" ;;
            --samples)        shift; CLI_SAMPLES="${1:-}" ;;
            --interval)       shift; CLI_INTERVAL="${1:-}" ;;
            --yes)            CONFIRM_YES=1 ;;
            --json)           OUTPUT_MODE="json"; COLOR_ENABLED=0 ;;
            --quiet)          QUIET=1 ;;
            --no-color)       COLOR_ENABLED=0 ;;
            *)
                echo "Unknown argument: '$1'" >&2
                CLI_ACTION="help"
                ;;
        esac
        shift
    done
}

# _cli_take_optional_value <out_var_name> <args...>
#   Args: $1 = name of the variable to assign, "$@" = remaining argv (with the
#   flag itself still at position 1)
#   Returns: 0 and sets <out_var_name> if $2 looks like a value (not another
#   --flag); 1 (no shift needed) if $2 is absent or itself a flag.
#   This lets flags like --discover / --geolocate / --live-bandwidth take an
#   optional positional value without swallowing the next real flag.
_cli_take_optional_value() {
    local out_var="$1"
    local candidate="${3:-}"
    if [[ -n "$candidate" && "${candidate:0:2}" != "--" ]]; then
        printf -v "$out_var" '%s' "$candidate"
        return 0
    fi
    return 1
}

# dispatch_cli
#   Args: none (reads $CLI_ACTION and the CLI_* globals)
#   Returns: the dispatched function's exit code; 1 if no action was set
dispatch_cli() {
    case "$CLI_ACTION" in
        help)                show_help ;;
        dashboard)           dashboard ;;
        interface_info)      interface_info ;;
        routing_table)       routing_table ;;
        local_discovery)     local_discovery ;;
        ping_host)           ping_host ;;
        trace_route)         trace_route ;;
        mtu_discovery)       mtu_discovery ;;
        dns_lookup)          dns_lookup ;;
        reverse_dns)         reverse_dns ;;
        whois_lookup)        whois_lookup ;;
        port_scan)           port_scan ;;
        service_scan)        service_scan ;;
        vuln_check)          vuln_check ;;
        http_check)          http_check ;;
        ssl_cert)            ssl_cert ;;
        geolocate)           geolocate ;;
        active_connections)  active_connections ;;
        listening_ports)     listening_ports ;;
        speed_test)          speed_test ;;
        live_bandwidth)      live_bandwidth ;;
        view_log)            view_log ;;
        export_result)       export_result "$CLI_INDEX" ;;
        "")                  return 1 ;;
        *)                   echo "Unhandled CLI action: $CLI_ACTION" >&2; return 1 ;;
    esac
}
