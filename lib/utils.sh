#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/utils.sh — Core utilities: OS detection, validation, sanitization,
#                logging (with rotation), config loading, history, JSON helpers,
#                spinner, connectivity checks.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# ─── OS Detection ─────────────────────────────────────────────────────────────
# detect_os
#   Args: none
#   Returns: 0
#   Side effects: sets global $OS to one of: linux, macos, bsd, unknown
detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Linux*)   OS="linux" ;;
        Darwin*)  OS="macos" ;;
        FreeBSD*|OpenBSD*|NetBSD*) OS="bsd" ;;
        *)        OS="unknown" ;;
    esac
    export OS
}

# ─── Input Sanitization & Validation ──────────────────────────────────────────
# sanitize_input <string>
#   Args: $1 = raw user input
#   Returns: prints sanitized string on stdout
#   Side effects: none
#   Strips shell metacharacters that have no legitimate place in a hostname,
#   IP, URL, CIDR range or port list: ; | & ` $ ( ) < > and line breaks.
#   This is defence in depth only: every value is also passed through a
#   validate_* function and always reaches external commands as a single
#   quoted argument, never through eval or a shell string.
sanitize_input() {
    local input="${1:-}"
    # shellcheck disable=SC2016  # the single-quoted set is literal on purpose
    printf '%s' "$input" | tr -d ';|&`$()<>\n\r'
}

# printable <string>
#   Args: $1 = untrusted string (e.g. a rejected CLI argument)
#   Returns: prints a copy that is safe to show through `echo -e`: control
#   characters (including ESC, so no terminal escape sequences) become '?'
#   and backslashes are doubled so echo -e prints them literally.
printable() {
    local s=""
    s=$(printf '%s' "${1:-}" | tr '[:cntrl:]' '?')
    printf '%s' "${s//\\/\\\\}"
}

# validate_ip <string>
#   Args: $1 = candidate string
#   Returns: 0 if a syntactically valid IPv4 or IPv6 address, 1 otherwise
validate_ip() {
    local ip="${1:-}"
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local o=""
        for o in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
            # 10# forces base 10 so "08" is not rejected as a bad octal literal
            (( 10#$o <= 255 )) || return 1
        done
        return 0
    fi
    _validate_ipv6 "$ip"
}

# _validate_ipv6 <string>
#   Args: $1 = candidate string
#   Returns: 0 for a plain (non-zoned, non-IPv4-mapped) IPv6 address made of
#   1-4 digit hex groups: either exactly 8 groups, or at most 7 groups with a
#   single "::" standing in for the rest. 1 otherwise.
_validate_ipv6() {
    local ip="${1:-}" head="" tail="" n=0
    local -r groups_re='^[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4})*$'
    [[ ${#ip} -ge 2 && ${#ip} -le 39 ]] || return 1
    if [[ "$ip" == *::* ]]; then
        head="${ip%%::*}"
        tail="${ip#*::}"
        [[ "$tail" == *::* ]] && return 1          # only one "::" allowed
        if [[ -n "$head" ]]; then
            [[ "$head" =~ $groups_re ]] || return 1
            n=$(( n + $(_count_groups "$head") ))
        fi
        if [[ -n "$tail" ]]; then
            [[ "$tail" =~ $groups_re ]] || return 1
            n=$(( n + $(_count_groups "$tail") ))
        fi
        (( n <= 7 ))
    else
        [[ "$ip" =~ $groups_re ]] || return 1
        (( $(_count_groups "$ip") == 8 ))
    fi
}

# _count_groups <colon-separated list>
#   Returns: prints the number of ':'-separated fields
_count_groups() {
    local colons="${1//[!:]/}"
    echo $(( ${#colons} + 1 ))
}

# validate_cidr <string>
#   Args: $1 = candidate string (e.g. 192.168.1.0/24)
#   Returns: 0 if valid IPv4 CIDR, 1 otherwise
validate_cidr() {
    local cidr="${1:-}"
    local ip_part="" prefix=""
    ip_part="${cidr%%/*}"
    prefix="${cidr#*/}"
    [[ "$cidr" == */* ]] || return 1
    validate_ip "$ip_part" || return 1
    [[ "$prefix" =~ ^[0-9]{1,2}$ ]] || return 1
    (( 10#$prefix <= 32 )) || return 1
    return 0
}

# validate_domain <string>
#   Args: $1 = candidate hostname/domain
#   Returns: 0 if it looks like a valid DNS name, 1 otherwise
validate_domain() {
    local d="${1:-}"
    [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] && return 0
    [[ "$d" == "localhost" ]] && return 0
    return 1
}

# validate_host <string>
#   Args: $1 = candidate host (IP or domain or "localhost")
#   Returns: 0 if valid, 1 otherwise
validate_host() {
    local h="${1:-}"
    [[ -z "$h" ]] && return 1
    validate_ip "$h" && return 0
    validate_domain "$h" && return 0
    return 1
}

# validate_url <string>
#   Args: $1 = candidate URL
#   Returns: 0 if it starts with http(s):// and contains no shell metacharacters
validate_url() {
    local u="${1:-}"
    local -r url_re='^https?://[A-Za-z0-9./_:%?=&#~+-]+$'
    [[ "$u" =~ $url_re ]] && return 0
    return 1
}

# validate_port <string>
#   Args: $1 = candidate TCP/UDP port
#   Returns: 0 if an integer in 1-65535, 1 otherwise
validate_port() {
    [[ "${1:-}" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

# validate_port_range <string>
#   Args: $1 = port or port range/list (e.g. 80, 1-1000, 22,80,443-445)
#   Returns: 0 if every comma-separated item is a port or an ascending
#   LOW-HIGH range of ports in 1-65535; 1 otherwise (empty items, "-",
#   open-ended ranges such as "-100" or "80-", or ports above 65535).
validate_port_range() {
    local p="${1:-}" item="" lo="" hi=""
    local -a items=()
    [[ "$p" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || return 1
    IFS=',' read -r -a items <<< "$p"
    for item in "${items[@]}"; do
        lo="${item%-*}"
        hi="${item#*-}"
        validate_port "$lo" && validate_port "$hi" || return 1
        (( 10#$lo <= 10#$hi )) || return 1
    done
    return 0
}

# validate_positive_int <string>
#   Args: $1 = candidate
#   Returns: 0 if a positive integer, 1 otherwise
#   Use this (and a 10# normalisation) before any untrusted value reaches
#   bash arithmetic: (( )), $(( )) and [[ -gt ]] evaluate a string such as
#   'x[$(cmd)]' as an expression and would run cmd.
validate_positive_int() {
    [[ "${1:-}" =~ ^[0-9]{1,18}$ ]] && (( 10#${1} > 0 ))
}

# validate_nonneg_int <string>
#   Args: $1 = candidate
#   Returns: 0 if an integer >= 0 (at most 18 digits), 1 otherwise
validate_nonneg_int() {
    [[ "${1:-}" =~ ^[0-9]{1,18}$ ]]
}

# validate_iface <string>
#   Args: $1 = candidate network interface name (eth0, en0, wlp2s0, utun3...)
#   Returns: 0 if it is a plausible interface name, 1 otherwise. Rejects '/',
#   '..' and a leading '-', since the name is used to build a /sys path and
#   is passed to netstat/awk.
validate_iface() {
    local i="${1:-}"
    [[ "$i" =~ ^[A-Za-z0-9][A-Za-z0-9_.:@-]{0,31}$ ]] || return 1
    [[ "$i" == *..* ]] && return 1
    return 0
}

# require_valid <value> <validator_fn> <label>
#   Args: $1 = value, $2 = name of validation function, $3 = human label for errors
#   Returns: 0 if valid; prints an error and returns 1 otherwise
require_valid() {
    local value="$1" validator="$2" label="$3"
    if ! "$validator" "$value"; then
        err "Invalid ${label}: '$(printable "$value")'"
        return 1
    fi
    return 0
}

# ─── Private IP Detection ─────────────────────────────────────────────────────
# is_private_ip <ip>
#   Args: $1 = IPv4 address
#   Returns: 0 if RFC1918 / loopback / link-local, 1 if public/unknown
is_private_ip() {
    local ip="${1:-}"
    [[ "$ip" =~ ^127\. ]] && return 0
    [[ "$ip" =~ ^10\. ]] && return 0
    [[ "$ip" =~ ^192\.168\. ]] && return 0
    [[ "$ip" =~ ^169\.254\. ]] && return 0
    if [[ "$ip" =~ ^172\.([0-9]{1,3})\. ]]; then
        local second="${BASH_REMATCH[1]}"
        (( second >= 16 && second <= 31 )) && return 0
    fi
    [[ "$ip" == "::1" ]] && return 0
    return 1
}

# warn_if_public_target <host>
#   Args: $1 = host (IP or domain) about to be scanned
#   Returns: 0 always
#   Side effects: resolves the host if needed and prints an aggressive warning
#   if the target does not appear to be a private/local address. Used before
#   port scans and vulnerability scans.
warn_if_public_target() {
    local host="$1" ip="$1"
    if ! validate_ip "$host"; then
        ip=$(resolve_host_to_ip "$host")
    fi
    if [[ -n "$ip" ]] && validate_ip "$ip" && ! is_private_ip "$ip"; then
        local line=""
        echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
        for line in "WARNING: $host ($ip) is NOT a private/local address." \
                    "Only scan systems you OWN or have WRITTEN permission to" \
                    "test. Unauthorized scanning may be illegal."; do
            # %-58s pads to the box width; a long hostname just widens the row.
            printf "${RED}${BOLD}║ %-58s ║${NC}\n" "$line"
        done
        echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
        return 1
    fi
    return 0
}

# resolve_host_to_ip <host>
#   Args: $1 = hostname or IP
#   Returns: prints the first resolved IPv4 address on stdout (best-effort)
resolve_host_to_ip() {
    local host="$1"
    if validate_ip "$host"; then
        echo "$host"; return 0
    fi
    if has dig; then
        dig +short A "$host" 2>/dev/null | grep -E '^[0-9]+\.' | head -1
    elif has getent; then
        getent ahostsv4 "$host" 2>/dev/null | awk '{print $1; exit}'
    elif has host; then
        host "$host" 2>/dev/null | awk '/has address/ {print $NF; exit}'
    fi
}

# ─── Logging & Rotation ───────────────────────────────────────────────────────
# rotate_log_if_needed
#   Args: none
#   Returns: 0
#   Side effects: truncates $LOG_FILE to the last MAX_LOG_LINES lines if it
#   exceeds MAX_LOG_LINES lines or MAX_LOG_SIZE bytes.
rotate_log_if_needed() {
    [[ -f "$LOG_FILE" ]] || return 0
    local size="" lines=""
    size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    size=${size//[[:space:]]/}
    lines=${lines//[[:space:]]/}
    if (( size > MAX_LOG_SIZE )) || (( lines > MAX_LOG_LINES )); then
        tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

# log <message...>
#   Args: message to record
#   Returns: 0
#   Side effects: appends a timestamped line to $LOG_FILE, rotating if needed
log() {
    local ts=""
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" >> "$LOG_FILE" 2>/dev/null
    rotate_log_if_needed
}

# ─── Target History ───────────────────────────────────────────────────────────
# remember_target <target>
#   Args: $1 = target string typed by the user
#   Returns: 0
#   Side effects: appends to $HISTORY_FILE, keeping only the most recent 10
#   unique entries (most recent last).
remember_target() {
    local target="$1"
    [[ -z "$target" ]] && return 0
    mkdir -p "$(dirname "$HISTORY_FILE")" 2>/dev/null
    touch "$HISTORY_FILE" 2>/dev/null
    grep -Fxv "$target" "$HISTORY_FILE" 2>/dev/null > "${HISTORY_FILE}.tmp" || true
    echo "$target" >> "${HISTORY_FILE}.tmp"
    tail -n 10 "${HISTORY_FILE}.tmp" > "$HISTORY_FILE" 2>/dev/null
    rm -f "${HISTORY_FILE}.tmp"
}

# recent_targets
#   Args: none
#   Returns: prints up to 10 recent targets, most recent first
recent_targets() {
    [[ -f "$HISTORY_FILE" ]] || return 0
    tac "$HISTORY_FILE" 2>/dev/null || tail -r "$HISTORY_FILE" 2>/dev/null
}

# ─── Configuration File ───────────────────────────────────────────────────────
# load_config
#   Args: none
#   Returns: 0
#   Side effects: reads $CONFIG_FILE (INI-style) and overrides defaults:
#   ping_count, ports, timeout, color, dns_server, log_file, log_max_size,
#   log_max_lines, speed_test_endpoints (comma separated).
# The settings assigned here are read by other modules (see SC2034 note in
# lib/cli.sh).
# shellcheck disable=SC2034
load_config() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    local line="" key="" value=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line%%;*}"
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^\[.*\]$ ]] && continue
        [[ "$line" != *"="* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        key="$(printf '%s' "$key" | sed -e 's/[[:space:]]*$//')"
        value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//')"
        # Numeric settings end up in bash arithmetic and in command
        # arguments, so each value is validated before it replaces a default;
        # an invalid value is reported and the default is kept.
        case "$key" in
            ping_count)            _config_set "$key" "$value" validate_positive_int DEFAULT_PING_COUNT ;;
            ports)                 _config_set "$key" "$value" validate_port_range DEFAULT_PORTS ;;
            timeout)               _config_set "$key" "$value" validate_positive_int DEFAULT_TIMEOUT ;;
            color)                 [[ "$value" =~ ^(0|false|off|no)$ ]] && COLOR_ENABLED=0 ;;
            colorblind_safe)       [[ "$value" =~ ^(1|true|on|yes)$ ]] && COLORBLIND_SAFE=1 ;;
            dns_server)            [[ -z "$value" ]] || _config_set "$key" "$value" validate_ip PREFERRED_DNS ;;
            log_file)              LOG_FILE="$value" ;;
            log_max_size)          _config_set "$key" "$value" validate_positive_int MAX_LOG_SIZE ;;
            log_max_lines)         _config_set "$key" "$value" validate_positive_int MAX_LOG_LINES ;;
            speed_test_endpoints)  _config_set_endpoints "$value" ;;
        esac
    done < "$CONFIG_FILE"
}

# _config_set <key> <value> <validator_fn> <var_name>
#   Args: config key (for the message), raw value, validation function, name
#   of the global to assign
#   Returns: 0; assigns <var_name> only if <validator_fn> accepts the value,
#   otherwise prints a warning to stderr. Integers are normalised to base 10
#   so a value like "010" cannot be read as octal later.
_config_set() {
    local key="$1" value="$2" validator="$3" var="$4"
    if "$validator" "$value"; then
        [[ "$value" =~ ^[0-9]+$ ]] && value=$(( 10#$value ))
        printf -v "$var" '%s' "$value"
    else
        printf 'networktool: ignoring invalid %s in %s: %s\n' \
            "$key" "$CONFIG_FILE" "$(printable "$value")" >&2
    fi
}

# _config_set_endpoints <comma-separated URLs>
#   Returns: 0; replaces SPEEDTEST_ENDPOINTS with the http(s) URLs from the
#   list, skipping (and reporting) anything that is not a valid URL. Keeps
#   the defaults if no entry is valid.
# shellcheck disable=SC2034  # SPEEDTEST_ENDPOINTS is read in lib/monitor.sh
_config_set_endpoints() {
    local -a entries=() good=()
    local u=""
    IFS=',' read -r -a entries <<< "$1"
    for u in "${entries[@]}"; do
        u="$(printf '%s' "$u" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$u" ]] && continue
        if validate_url "$u"; then
            good+=("$u")
        else
            printf 'networktool: ignoring invalid speed_test_endpoints entry in %s: %s\n' \
                "$CONFIG_FILE" "$(printable "$u")" >&2
        fi
    done
    [[ ${#good[@]} -gt 0 ]] && SPEEDTEST_ENDPOINTS=("${good[@]}")
    return 0
}

# write_default_config
#   Args: none
#   Returns: 0
#   Side effects: writes a commented example config to $CONFIG_FILE if absent
write_default_config() {
    [[ -f "$CONFIG_FILE" ]] && return 0
    mkdir -p "$(dirname "$CONFIG_FILE")" 2>/dev/null
    cat > "$CONFIG_FILE" <<'EOF'
# Network Tool Pro configuration
# Lines starting with # or ; are comments.

[general]
ping_count = 4
ports = 1-1000
timeout = 10
color = on
colorblind_safe = off
dns_server =
log_max_size = 5242880
log_max_lines = 1000

[speedtest]
speed_test_endpoints = https://speed.hetzner.de/10MB.bin,https://ash-speed.hetzner.com/10MB.bin,https://bouygues.testdebit.info/10M.iso,https://nbg1-speed.hetzner.com/10MB.bin
EOF
}

# ─── JSON Helpers ──────────────────────────────────────────────────────────────
# json_escape <string>
#   Args: $1 = raw string
#   Returns: prints a JSON-safe escaped string (no surrounding quotes)
json_escape() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/}"
    # Any other control character (ESC from coloured tool output, NUL, form
    # feed, ...) is invalid inside a JSON string; drop it.
    s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037\177')"
    s="$(printf '%s' "$s" | awk '{printf "%s\\n", $0}')"
    s="${s%\\n}"
    printf '%s' "$s"
}

# json_output <tool> <target> <success:true|false> <data_json_fragment>
#   Args: tool name, target string, success bool literal, a JSON object literal
#   Returns: prints one JSON object line to stdout
json_output() {
    local tool="$1" target="$2" success="$3" data="$4" ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')
    printf '{"tool":"%s","target":"%s","success":%s,"data":%s,"timestamp":"%s"}\n' \
        "$(json_escape "$tool")" "$(json_escape "$target")" "$success" "$data" "$ts" >&"${JSON_FD:-1}"
}

# json_output_raw <tool> <target> <success> <raw_text>
#   Args: tool name, target, success bool literal, arbitrary raw text
#   Returns: prints a JSON object with data={"raw": "..."}
json_output_raw() {
    local tool="$1" target="$2" success="$3" raw="$4"
    json_output "$tool" "$target" "$success" "{\"raw\":\"$(json_escape "$raw")\"}"
}

# ─── Command Availability ─────────────────────────────────────────────────────
# has <command>
#   Returns: 0 if command exists on PATH
has() { command -v "$1" >/dev/null 2>&1; }

# need <command...>
#   Args: one or more required commands
#   Returns: 0 if all present; otherwise prints an error with install hints
need() {
    local missing=()
    for t in "$@"; do has "$t" || missing+=("$t"); done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing required tool(s): ${missing[*]}"
        case "$OS" in
            linux) warn "Install with: sudo apt install ${missing[*]}" ;;
            macos) warn "Install with: brew install ${missing[*]}" ;;
            *)     warn "Please install: ${missing[*]}" ;;
        esac
        return 1
    fi
}

# ─── Connectivity Check ────────────────────────────────────────────────────────
# check_connectivity
#   Args: none
#   Returns: 0 if at least one of several well-known endpoints responds,
#   1 if all are unreachable ("offline"). Probes in parallel.
#   Side effects: sets global CONNECTIVITY_RESULTS array of "host:up|down"
check_connectivity() {
    local targets=(8.8.8.8 1.1.1.1 9.9.9.9)
    local tmp="$TEMP_DIR/connectivity"
    mkdir -p "$tmp"
    local t pid pids=()
    for t in "${targets[@]}"; do
        ( ping -c1 -W2 "$t" >/dev/null 2>&1 && echo up > "$tmp/$t" || echo down > "$tmp/$t" ) &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
    CONNECTIVITY_RESULTS=()
    local any_up=1
    for t in "${targets[@]}"; do
        local state=""
        state=$(cat "$tmp/$t" 2>/dev/null || echo down)
        CONNECTIVITY_RESULTS+=("$t:$state")
        [[ "$state" == "up" ]] && any_up=0
    done
    return $any_up
}

# run_with_timeout <seconds> <command...>
#   Args: $1 = timeout in seconds, remaining = command to run
#   Returns: runs the command bounded by GNU `timeout`/`gtimeout` when either
#   is available; falls back to running unbounded (best-effort) on systems
#   that have neither (e.g. a bare macOS without coreutils).
run_with_timeout() {
    local secs="$1"; shift
    if has timeout; then
        timeout "$secs" "$@"
    elif has gtimeout; then
        gtimeout "$secs" "$@"
    else
        "$@"
    fi
}

# ─── Progress Spinner ──────────────────────────────────────────────────────────
# progress_spinner <pid> [message]
#   Args: $1 = PID of a background job to wait on, $2 = optional status message
#   Returns: the wrapped process's exit code
#   Side effects: renders a spinner on stderr while the process runs (human
#   mode only); silent under --json/--quiet.
progress_spinner() {
    local pid="$1" msg="${2:-Working...}"
    if [[ "$OUTPUT_MODE" == "json" || "$QUIET" -eq 1 || ! -t 2 ]]; then
        wait "$pid" 2>/dev/null
        return $?
    fi
    local frames="|/-\\" i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%s %s ' "${frames:i++%${#frames}:1}" "$msg" >&2
        sleep 0.15
    done
    printf '\r%*s\r' "$(( ${#msg} + 4 ))" '' >&2
    wait "$pid" 2>/dev/null
    return $?
}

# run_with_spinner <message> <command...>
#   Args: $1 = status message, remaining = command to run
#   Returns: the command's exit code; prints the command's captured stdout+stderr
#   Side effects: writes/removes a scratch file under $TEMP_DIR
run_with_spinner() {
    local msg="$1"; shift
    local tmp="" rc=""
    tmp=$(mktemp "$TEMP_DIR/spinner.XXXXXX" 2>/dev/null) || tmp="$TEMP_DIR/spinner.$$"
    ( "$@" >"$tmp" 2>&1 ) &
    local pid=$!
    progress_spinner "$pid" "$msg"
    rc=$?
    cat "$tmp" 2>/dev/null
    rm -f "$tmp"
    return $rc
}
