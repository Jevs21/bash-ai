#!/bin/bash
# example.sh - Categorize financial transactions using a local model with ai.sh

set -euo pipefail

INPUT_FILE="${1:-}"
OUTPUT_FILE="${2:-categories_output.txt}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_CMD="$SCRIPT_DIR/ai.sh"

PROMPT_PREFIX="Categorize this financial transaction into exactly one category. Reply with ONLY the category name, nothing else.

Categories: Government Benefit, Transfer In, Transfer Out, Rent, Insurance, Student Loan, Payroll, Investment, Internal Transfer, Interest Income, Interest Expense, Credit Card Payment, Subscription, Food & Dining, Groceries, Alcohol, Transportation, Transit, Parking, Gas, Shopping, Entertainment, Gaming, Healthcare, Pet, Telecommunications, Bank Fee, Bank Rebate, Cheque Deposit, Office Supplies, Clothing, Personal Care, Home & Garden, Flowers, Automotive, Advertising, Events, Unknown

Transaction: "

[[ -z "$INPUT_FILE" ]] && { echo "Usage: $0 <input_file> [output_file]"; exit 1; }
[[ ! -f "$INPUT_FILE" ]] && { echo "Error: File '$INPUT_FILE' not found"; exit 1; }
[[ ! -x "$AI_CMD" ]] && { echo "Error: ai.sh not found at $AI_CMD"; exit 1; }

CACHE_FILE=$(mktemp)
trap 'rm -f "$CACHE_FILE"' EXIT

cache_get() { grep -F "	$1	" "$CACHE_FILE" 2>/dev/null | cut -f3 || true; }
cache_set() { printf '%s\t%s\t%s\n' "x" "$1" "$2" >> "$CACHE_FILE"; }

total=$(grep -c '' "$INPUT_FILE" || echo 0)
current=0
hits=0

: > "$OUTPUT_FILE"
echo "Processing $total lines -> $OUTPUT_FILE"

while IFS= read -r line || [[ -n "$line" ]]; do
    ((++current))

    if [[ -z "$line" ]]; then
        echo "Unknown" >> "$OUTPUT_FILE"
        echo "[$current/$total] (empty) -> Unknown"
        continue
    fi

    cached=$(cache_get "$line")
    if [[ -n "$cached" ]]; then
        ((++hits))
        echo "$cached" >> "$OUTPUT_FILE"
        echo "[$current/$total] $line -> $cached (cached)"
        continue
    fi

    category=$("$AI_CMD" --provider local --prompt "${PROMPT_PREFIX}${line}\"" 2>/dev/null | xargs || true)
    category="${category:-Unknown}"
    cache_set "$line" "$category"

    echo "$category" >> "$OUTPUT_FILE"
    echo "[$current/$total] $line -> $category"
done < "$INPUT_FILE"

echo ""
echo "Done! API calls: $((current - hits)), Cache hits: $hits"
