#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/dns.sh — DNS lookup, reverse DNS, whois.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# ═════════════════════════════════════════════════════════════════════════════
# 8. DNS LOOKUP
#   Args: none; reads $CLI_TARGET when $NONINTERACTIVE=1 (CLI: --dns DOMAIN)
#   BUGFIX: dig's positional syntax is `dig NAME TYPE`, not `dig TYPE NAME` —
#   the original swapped them, silently returning empty results.
# ═════════════════════════════════════════════════════════════════════════════
dns_lookup() {
    local domain=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        domain="$CLI_TARGET"
    else
        domain=$(prompt "Domain to resolve" "google.com")
    fi

    if ! validate_domain "$domain"; then
        err "Invalid domain: '$domain'"
        return 1
    fi

    log "DNS lookup → $domain"
    section "DNS Lookup → $domain"

    local raw="" json_records="[" first=1
    if has dig; then
        local rtype="" result="" rec=""
        for rtype in A AAAA MX NS TXT; do
            result=$(dig +short "$domain" "$rtype" 2>/dev/null)
            if [[ -n "$result" ]]; then
                echo -e "  ${BOLD}${rtype}${NC}:"
                echo "$result" | sed 's/^/    /'
                raw+="${rtype}:
${result}
"
                while IFS= read -r rec; do
                    [[ -z "$rec" ]] && continue
                    [[ $first -eq 0 ]] && json_records+=","
                    json_records+=$(printf '{"type":"%s","value":"%s"}' "$rtype" "$(json_escape "$rec")")
                    first=0
                done <<< "$result"
            fi
        done

        section "DNS Query Stats"
        dig "$domain" 2>/dev/null | awk '/^;; (Query|SERVER|WHEN|MSG SIZE)/ {print "  "$0}'
    elif has nslookup; then
        raw=$(nslookup "$domain" 2>&1)
        echo "$raw"
        # Best-effort JSON: pull addresses out of the answer section only
        # (skip the resolver's own "Server:"/"Address:" lines up top).
        local answer_section="" addr=""
        answer_section=$(echo "$raw" | awk '/^Name:/{f=1} f')
        while IFS= read -r addr; do
            [[ -z "$addr" ]] && continue
            [[ $first -eq 0 ]] && json_records+=","
            json_records+=$(printf '{"type":"A/AAAA","value":"%s"}' "$(json_escape "$addr")")
            first=0
        done < <(echo "$answer_section" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}|([0-9A-Fa-f]{1,4}:){2,7}[0-9A-Fa-f]{1,4}')
    elif has host; then
        raw=$(host -a "$domain" 2>&1)
        echo "$raw"
        local addr=""
        while IFS= read -r addr; do
            [[ -z "$addr" ]] && continue
            [[ $first -eq 0 ]] && json_records+=","
            json_records+=$(printf '{"type":"A/AAAA","value":"%s"}' "$(json_escape "$addr")")
            first=0
        done < <(echo "$raw" | grep -Eo 'has (IPv6 )?address [^ ]+' | awk '{print $NF}')
    else
        err "No DNS tool available (dig/nslookup/host)."
        return 1
    fi
    json_records+="]"

    section "Configured DNS Servers"
    get_dns_servers | sed 's/^/  /'

    push_result "DNS lookup $domain" "$raw"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output "dns_lookup" "$domain" "true" "{\"records\":${json_records}}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 9. REVERSE DNS
#   Args: none; reads $CLI_TARGET when $NONINTERACTIVE=1 (CLI: --reverse-dns IP)
# ═════════════════════════════════════════════════════════════════════════════
reverse_dns() {
    local ip=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        ip="$CLI_TARGET"
    else
        ip=$(prompt "IP address" "8.8.8.8")
    fi

    if ! validate_ip "$ip"; then
        err "Invalid IP address: '$ip'"
        return 1
    fi

    log "Reverse DNS → $ip"
    section "Reverse DNS → $ip"

    local hostname=""
    if has dig; then
        hostname=$(dig +short -x "$ip" 2>/dev/null)
    elif has host; then
        hostname=$(host "$ip" 2>/dev/null | awk '/pointer/ {print $NF}')
    elif has nslookup; then
        # BIND-style nslookup (Linux/macOS/BSD): "8.8.8.8.in-addr.arpa name = dns.google."
        hostname=$(nslookup "$ip" 2>/dev/null | awk -F'= ' '/name = / {print $2}')
        # Fallback for nslookup implementations that print "Name:    dns.google" instead.
        [[ -z "$hostname" ]] && hostname=$(nslookup "$ip" 2>/dev/null | awk -F': *' '/^Name:/ {print $2}')
    else
        err "No DNS tool found (dig/host/nslookup)."
        return 1
    fi
    hostname="${hostname%.}"

    if [[ -n "$hostname" ]]; then
        ok "Hostname: ${BOLD}$hostname${NC}"
    else
        warn "No PTR record found."
    fi

    push_result "Reverse DNS $ip → ${hostname:-none}" "Reverse DNS $ip: ${hostname:-none}"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local success=""
        [[ -n "$hostname" ]] && success=true || success=false
        json_output "reverse_dns" "$ip" "$success" "{\"hostname\":\"$(json_escape "$hostname")\"}"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# 10. WHOIS
#   Args: none; reads $CLI_TARGET when $NONINTERACTIVE=1 (CLI: --whois TARGET)
#   BUGFIX: the RDAP fallback used to mangle the domain (`.` → `DOT`) before
#   querying rdap.org, which meant the fallback could never work. The real
#   domain is now passed through unmodified.
# ═════════════════════════════════════════════════════════════════════════════
whois_lookup() {
    local target=""
    if [[ "$NONINTERACTIVE" -eq 1 ]]; then
        target="$CLI_TARGET"
    else
        target=$(prompt "Domain or IP" "google.com")
    fi

    if ! validate_host "$target"; then
        err "Invalid domain or IP: '$target'"
        return 1
    fi

    log "Whois → $target"
    section "Whois → $target"

    local raw=""
    if has whois; then
        raw=$(whois "$target" 2>/dev/null)
        echo "$raw" | grep -Ei \
            '(registrar|registrant|organization|country|creation|expir|updated|name.server|netname|inetnum|route|aut-num|descr|abuse)' \
            | head -40
        ok "Full result available via: whois $target"
    else
        info "whois not installed — using online RDAP fallback..."
        if has curl; then
            raw=$(curl -sL --max-time 10 "https://rdap.org/domain/${target}" 2>/dev/null)
            if [[ -n "$raw" ]]; then
                if has python3; then
                    echo "$raw" | python3 -c \
                        "import sys, json
d = json.load(sys.stdin)
for k, v in d.items():
    if isinstance(v, str):
        print(f'  {k}: {v}')" 2>/dev/null || echo "$raw"
                else
                    echo "$raw" | grep -Eo '"[^"]+":"[^"]*"' | sed 's/"//g; s/:/: /' | head -20
                fi
            else
                err "RDAP lookup failed."
            fi
        else
            err "Neither whois nor curl available."
            case "$OS" in
                linux) warn "Install: sudo apt install whois" ;;
                macos) warn "Install: brew install whois" ;;
            esac
            return 1
        fi
    fi

    push_result "Whois $target" "$raw"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local success=""
        [[ -n "$raw" ]] && success=true || success=false
        json_output_raw "whois" "$target" "$success" "$raw"
    fi
}
