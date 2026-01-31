#!/usr/bin/env bash
# ai.sh - Unified AI CLI connector

set -euo pipefail

# Defaults
: "${AI_PROVIDER:=local}"
: "${AI_TIMEOUT:=120}"
: "${AI_OLLAMA_HOST:=http://localhost:11434}"
: "${AI_OPENAI_API_BASE:=https://api.openai.com/v1}"
: "${AI_ANTHROPIC_API_BASE:=https://api.anthropic.com/v1}"

die() { echo "error: $*" >&2; exit 1; }

usage() {
    cat >&2 <<'EOF'
Usage: ai [OPTIONS]

Options:
  --provider <provider>   local, openai, anthropic, claude (default: $AI_PROVIDER)
  --model <model>         Model name (provider-specific default if omitted)
  --prompt <text>         Prompt text (or pipe to stdin)
  --timeout <seconds>     Request timeout (default: 120)
  --usage                 Show usage stats (tokens, duration, speed)
  -h, --help              Show this help

Environment: AI_PROVIDER, AI_TIMEOUT, AI_OLLAMA_HOST,
             AI_OPENAI_API_KEY, AI_OPENAI_API_BASE,
             AI_ANTHROPIC_API_KEY, AI_ANTHROPIC_API_BASE
EOF
    exit 1
}

# Parse arguments
PROVIDER="" MODEL="" PROMPT="" TIMEOUT="$AI_TIMEOUT" SHOW_USAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --provider) PROVIDER="$2"; shift 2 ;;
        --model)    MODEL="$2"; shift 2 ;;
        --prompt)   PROMPT="$2"; shift 2 ;;
        --timeout)  TIMEOUT="$2"; shift 2 ;;
        --usage)    SHOW_USAGE=1; shift ;;
        -h|--help)  usage ;;
        *)          die "Unknown option: $1" ;;
    esac
done

PROVIDER="${PROVIDER:-$AI_PROVIDER}"
[[ -z "$PROMPT" ]] && { [[ -t 0 ]] && die "No prompt provided"; PROMPT=$(cat); }
[[ -z "$PROMPT" ]] && die "Empty prompt"

command -v jq &>/dev/null || die "jq is required"

# Make API request and extract response
api_call() {
    local response
    response=$(curl -sf --max-time "$TIMEOUT" "$@" 2>/dev/null) || die "Request failed"
    echo "$response"
}

# Print usage stats line
print_usage() {
    local time_s="$1" in_tok="$2" out_tok="$3" tok_s="$4" stop="$5"
    local stats="time: ${time_s}s | in: ${in_tok} | out: ${out_tok}"
    [[ -n "$tok_s" ]] && stats="$stats | tok/s: ${tok_s}"
    [[ -n "$stop" ]] && stats="$stats | stop: ${stop}"
    echo "---"
    echo "$stats"
}

[[ -n "$SHOW_USAGE" ]] && start_time=$(date +%s)

case "$PROVIDER" in
    local|ollama)
        MODEL="${MODEL:-gemma3:4b}"
        payload=$(jq -nc --arg m "$MODEL" --arg p "$PROMPT" '{model:$m,prompt:$p,stream:false}')
        response=$(api_call -X POST "${AI_OLLAMA_HOST}/api/generate" \
            -H "Content-Type: application/json" -d "$payload")
        echo "$response" | jq -r '.response // empty'
        if [[ -n "$SHOW_USAGE" ]]; then
            duration=$(( $(date +%s) - start_time ))
            in_tok=$(echo "$response" | jq -r '.prompt_eval_count // "n/a"')
            out_tok=$(echo "$response" | jq -r '.eval_count // "n/a"')
            eval_dur=$(echo "$response" | jq -r '.eval_duration // 0')
            tok_s=""
            if [[ "$eval_dur" != "0" && "$out_tok" != "n/a" && "$eval_dur" -gt 0 ]]; then
                tok_s=$(( out_tok * 1000000000 / eval_dur ))
            fi
            print_usage "$duration" "$in_tok" "$out_tok" "$tok_s" ""
        fi
        ;;
    openai)
        [[ -z "${AI_OPENAI_API_KEY:-}" ]] && die "AI_OPENAI_API_KEY required"
        MODEL="${MODEL:-gpt-4o}"
        payload=$(jq -nc --arg m "$MODEL" --arg p "$PROMPT" '{model:$m,messages:[{role:"user",content:$p}]}')
        response=$(api_call -X POST "${AI_OPENAI_API_BASE}/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $AI_OPENAI_API_KEY" -d "$payload")
        echo "$response" | jq -r '.choices[0].message.content // empty'
        if [[ -n "$SHOW_USAGE" ]]; then
            duration=$(( $(date +%s) - start_time ))
            in_tok=$(echo "$response" | jq -r '.usage.prompt_tokens // "n/a"')
            out_tok=$(echo "$response" | jq -r '.usage.completion_tokens // "n/a"')
            stop=$(echo "$response" | jq -r '.choices[0].finish_reason // empty')
            print_usage "$duration" "$in_tok" "$out_tok" "" "$stop"
        fi
        ;;
    anthropic)
        [[ -z "${AI_ANTHROPIC_API_KEY:-}" ]] && die "AI_ANTHROPIC_API_KEY required"
        MODEL="${MODEL:-claude-sonnet-4-20250514}"
        payload=$(jq -nc --arg m "$MODEL" --arg p "$PROMPT" '{model:$m,max_tokens:4096,messages:[{role:"user",content:$p}]}')
        response=$(api_call -X POST "${AI_ANTHROPIC_API_BASE}/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $AI_ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" -d "$payload")
        echo "$response" | jq -r '.content[0].text // empty'
        if [[ -n "$SHOW_USAGE" ]]; then
            duration=$(( $(date +%s) - start_time ))
            in_tok=$(echo "$response" | jq -r '.usage.input_tokens // "n/a"')
            out_tok=$(echo "$response" | jq -r '.usage.output_tokens // "n/a"')
            stop=$(echo "$response" | jq -r '.stop_reason // empty')
            print_usage "$duration" "$in_tok" "$out_tok" "" "$stop"
        fi
        ;;
    claude|claude_code)
        command -v claude &>/dev/null || die "claude CLI not found"
        if [[ -n "$MODEL" ]]; then
            response=$(echo "$PROMPT" | claude -p --model "$MODEL")
        else
            response=$(echo "$PROMPT" | claude -p)
        fi
        echo "$response"
        if [[ -n "$SHOW_USAGE" ]]; then
            duration=$(( $(date +%s) - start_time ))
            in_tok=$(( ${#PROMPT} / 4 ))
            out_tok=$(( ${#response} / 4 ))
            print_usage "$duration" "~$in_tok" "~$out_tok" "" ""
        fi
        ;;
    *)
        die "Unknown provider: $PROVIDER (valid: local, openai, anthropic, claude)"
        ;;
esac
