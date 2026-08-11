#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
# lib/output.sh — Result stack (so any previous result can be exported by
#                 index), log viewer, export-to-file.
# Sourced by networktool.sh. Not meant to be executed directly.
# ═════════════════════════════════════════════════════════════════════════════

# shellcheck shell=bash

# Global result stack. Parallel arrays: label (short, for status bar/menu) and
# content (full text captured from the command). Index 0 = oldest.
RESULT_LABELS=()
RESULT_CONTENTS=()

# push_result <label> <content>
#   Args: $1 = short human label (e.g. "Ping 8.8.8.8 — 0% loss")
#         $2 = full captured output for export
#   Returns: 0
#   Side effects: appends to the global result stack
push_result() {
    local label="$1" content="$2"
    RESULT_LABELS+=("$label")
    RESULT_CONTENTS+=("$content")
    LAST_OUTPUT="$content"
}

# view_log
#   Args: none
#   Returns: 0
#   Side effects: prints the last 30 log entries (human) or a JSON array (json)
view_log() {
    log "View log"
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        local lines=""
        if [[ -f "$LOG_FILE" ]]; then
            lines=$(tail -30 "$LOG_FILE" 2>/dev/null)
        else
            lines=""
        fi
        json_output_raw "view_log" "$LOG_FILE" "true" "$lines"
        return 0
    fi
    section "Last 30 Log Entries — $LOG_FILE"
    if [[ -f "$LOG_FILE" ]]; then
        tail -30 "$LOG_FILE"
    else
        warn "No log file found yet."
    fi
    push_result "View log" "$(tail -30 "$LOG_FILE" 2>/dev/null)"
}

# export_result [index]
#   Args: $1 = optional 1-based index into the result stack (default: last)
#   Returns: 0 on success, 1 if nothing to export or index out of range
#   Side effects: writes the chosen result to $RESULTS_FILE
export_result() {
    local idx="${1:-}"
    local count=${#RESULT_CONTENTS[@]}
    if [[ $count -eq 0 ]]; then
        warn "No result to export. Run a diagnostic first."
        return 1
    fi

    if [[ -z "$idx" && "$NONINTERACTIVE" -ne 1 && "$OUTPUT_MODE" != "json" && "$QUIET" -ne 1 ]]; then
        echo -e "  ${BOLD}Available results:${NC}"
        local i=""
        for ((i = 0; i < count; i++)); do
            echo -e "    ${GRAY}$((i + 1)))${NC} ${RESULT_LABELS[$i]}"
        done
        idx=$(prompt "Index to export" "$count")
    fi
    idx="${idx:-$count}"

    if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > count )); then
        err "Invalid index: '$idx' (valid range: 1-$count)"
        return 1
    fi

    local content="${RESULT_CONTENTS[$((idx - 1))]}"
    echo "$content" > "$RESULTS_FILE"
    ok "Result #$idx saved to: $RESULTS_FILE"
    [[ "$OUTPUT_MODE" == "json" ]] && json_output "export_result" "$RESULTS_FILE" "true" "{\"index\":$idx}"
    return 0
}
