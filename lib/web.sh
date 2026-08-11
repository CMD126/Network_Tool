#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/web.sh — HTTP check, SSL certificate inspection, IP geolocation.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# parse_cert_date <openssl_date_string>
#   Args: $1 = a date string as emitted by `openssl x509 -noout -text`, e.g.
#   "Jun  1 12:00:00 2025 GMT" (note the double space before single-digit days)
#   Returns: prints the epoch seconds on stdout, or 0 if unparseable
#   Tries, in order: GNU `date -d` (Linux, and macOS if gdate/coreutils is
#   installed), then BSD/macOS `date -j -f` with a couple of plausible format
#   strings, since openssl's space-padded day breaks a naive `%d` match.
parse_cert_date() {
    local raw="${1:-}" normalized epoch=""
    [[ -z "$raw" ]] && { echo 0; return; }
    normalized="$(echo "$raw" | tr -s ' ')"

    if has gdate; then
        epoch=$(gdate -d "$normalized" +%s 2>/dev/null)
    fi
    if [[ -z "$epoch" ]]; then
        epoch=$(date -d "$normalized" +%s 2>/dev/null)
    fi
    if [[ -z "$epoch" ]]; then
        local fmt=""
        for fmt in "%b %d %T %Y %Z" "%b %e %T %Y %Z" "%b %d %T %Y"; do
            epoch=$(date -j -f "$fmt" "$normalized" +%s 2>/dev/null) && [[ -n "$epoch" ]] && break
        done
    fi
    echo "${epoch:-0}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 14. HTTP CHECK
#   Args: none; reads $CLI_TARGET when $NONINTERACTIVE=1
#   CLI: --http URL [--json]
# ═════════════════════════════════════════════════════════════════════════════
http_check() {
    if ! need curl; then return 1; fi

    local url=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        url="$CLI_TARGET"
    else
        url=$(prompt "URL" "https://example.com")
    fi
    [[ "$url" != http* ]] && url="https://$url"

    if ! validate_url "$url"; then
        err "Invalid URL: '$url'"
        return 1
    fi

    log "HTTP check → $url"
    section "HTTP Check → $url"
    info "Sending request..."

    local out=""
    out=$(curl -siL --max-time 15 \
        -A "NetworkTool/$VERSION" \
        -w "\n\n--- CURL STATS ---\nHTTP Code: %{http_code}\nTotal Time: %{time_total}s\nRedirect URL: %{url_effective}\nSize: %{size_download} bytes\nSpeed: %{speed_download} bytes/s\n" \
        "$url" 2>/dev/null)

    if [[ "$OUTPUT_MODE" != "json" && "$QUIET" -ne 1 ]]; then
        echo "$out" | awk -v y="$YELLOW" -v c="$CYAN" -v b="$BLUE" -v g="$GREEN" -v nc="$NC" '
            /^HTTP\// { print y $0 nc; next }
            /^(Date|Server|Content-Type|Location|X-Frame|Strict-Transport|X-Content-Type|Content-Security|Cache-Control):/ { print "  " c $0 nc; next }
            /^--- CURL STATS ---/ { print "\n" b $0 nc; next }
            /^(HTTP Code|Total Time|Redirect|Size|Speed):/ { print "  " g $0 nc; next }
        '
    fi

    local code="" time_total="" size=""
    code=$(echo "$out" | grep -m1 '^HTTP Code:' | awk '{print $NF}')
    time_total=$(echo "$out" | grep -m1 '^Total Time:' | awk '{print $NF}')
    size=$(echo "$out" | grep -m1 '^Size:' | awk '{print $2}')

    push_result "HTTP check $url — ${code:-?}" "$out"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local success=""
        [[ "$code" =~ ^[23] ]] && success=true || success=false
        json_output "http_check" "$url" "$success" \
            "$(printf '{"status_code":"%s","time_total":"%s","size_bytes":"%s"}' \
                "$(json_escape "${code:-}")" "$(json_escape "${time_total:-}")" "$(json_escape "${size:-}")")"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# 15. SSL CERTIFICATE
#   Args: none; reads $CLI_TARGET/$CLI_PORT when $NONINTERACTIVE=1
#   CLI: --ssl HOST [--port N]
# ═════════════════════════════════════════════════════════════════════════════
ssl_cert() {
    if ! need openssl; then return 1; fi

    local host="" port=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        host="$CLI_TARGET"
        port="${CLI_PORT:-443}"
    else
        host=$(prompt "Hostname" "google.com")
        port=$(prompt "Port" "443")
    fi

    if ! validate_host "$host"; then
        err "Invalid hostname: '$host'"
        return 1
    fi
    validate_positive_int "$port" || port=443

    log "SSL check → $host:$port"
    section "SSL Certificate → $host:$port"

    local raw=""
    raw=$(echo | run_with_timeout "$DEFAULT_TIMEOUT" openssl s_client \
        -connect "${host}:${port}" -servername "$host" 2>/dev/null \
        | openssl x509 -noout -text 2>/dev/null)

    if [[ -z "$raw" ]]; then
        err "Could not retrieve certificate."
        [[ "$OUTPUT_MODE" == "json" ]] && json_output "ssl_cert" "${host}:${port}" "false" "{}"
        return 1
    fi

    local subject="" issuer="" not_before="" not_after="" sans=""
    subject=$(echo "$raw" | grep 'Subject:' | head -1 | sed 's/.*Subject: //')
    issuer=$(echo "$raw" | grep 'Issuer:' | head -1 | sed 's/.*Issuer: //')
    not_before=$(echo "$raw" | grep 'Not Before' | sed 's/.*Not Before: //')
    not_after=$(echo "$raw" | grep 'Not After' | sed 's/.*Not After : //')
    sans=$(echo "$raw" | grep -A1 'Subject Alternative Name' | tail -1 | tr ',' '\n' | grep DNS | sed 's/.*DNS:/  /' | head -10)

    ok "Subject   : $subject"
    ok "Issuer    : $issuer"
    ok "Valid From: $not_before"

    local exp_epoch="" now_epoch="" days_left=""
    exp_epoch=$(parse_cert_date "$not_after")
    now_epoch=$(date +%s)
    days_left=$(( (exp_epoch - now_epoch) / 86400 ))

    if [[ "$exp_epoch" -eq 0 ]]; then
        warn "Expiry    : $not_after  (could not parse expiry date on this platform)"
    elif [[ $days_left -lt 0 ]]; then
        err "Expiry    : $not_after  ${RED}EXPIRED${NC}"
    elif [[ $days_left -lt 30 ]]; then
        warn "Expiry    : $not_after  ${YELLOW}(expires in ${days_left} days)${NC}"
    else
        ok "Expiry    : $not_after  ${GREEN}(${days_left} days remaining)${NC}"
    fi

    if [[ "$OUTPUT_MODE" != "json" && "$QUIET" -ne 1 ]]; then
        echo -e "\n${BOLD}SANs:${NC}"
        echo "$sans"
    fi

    section "Cipher Suite"
    local cipher_info=""
    cipher_info=$(echo | run_with_timeout "$DEFAULT_TIMEOUT" openssl s_client \
        -connect "${host}:${port}" -servername "$host" 2>/dev/null \
        | grep -E '(Cipher|Protocol|Verify)' | head -5)
    echo "$cipher_info"

    push_result "SSL $host:$port — ${days_left}d left" "SSL check $host:$port — $days_left days left"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        json_output "ssl_cert" "${host}:${port}" "true" \
            "$(printf '{"subject":"%s","issuer":"%s","not_before":"%s","not_after":"%s","days_left":%d}' \
                "$(json_escape "$subject")" "$(json_escape "$issuer")" \
                "$(json_escape "$not_before")" "$(json_escape "$not_after")" "$days_left")"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# 16. IP GEOLOCATION
#   Args: none; reads $CLI_TARGET when $NONINTERACTIVE=1 (blank = own public IP)
#   CLI: --geolocate [IP]
# ═════════════════════════════════════════════════════════════════════════════
geolocate() {
    if ! need curl; then return 1; fi

    local ip=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        ip="${CLI_TARGET:-}"
    else
        ip=$(prompt "IP address (blank = your public IP)" "")
    fi
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
    fi
    if ! validate_ip "$ip"; then
        err "Invalid IP address: '$ip'"
        return 1
    fi

    log "Geolocation → $ip"
    section "IP Geolocation → $ip"

    local data=""
    data=$(curl -s --max-time 10 "https://ipinfo.io/${ip}/json" 2>/dev/null)

    if [[ -n "$data" && "$OUTPUT_MODE" != "json" ]]; then
        if has python3; then
            echo "$data" | python3 -c "
import sys, json
d = json.load(sys.stdin)
fields = ['ip','city','region','country','org','postal','timezone','loc']
for f in fields:
    if f in d:
        print(f'  {f:<12}: {d[f]}')
" 2>/dev/null || echo "$data" | grep -Eo '\"[^\"]+\":\"[^\"]+\"' | sed 's/"//g; s/:/: /' | head -15
        else
            echo "$data" | grep -Eo '"[^"]+":"[^"]+"' | sed 's/"//g; s/:/: /' | head -15
        fi
    elif [[ -z "$data" ]]; then
        err "Geolocation lookup failed."
    fi

    push_result "Geolocation $ip" "$data"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        json_output_raw "geolocate" "$ip" "$( [[ -n "$data" ]] && echo true || echo false )" "$data"
    fi
}
