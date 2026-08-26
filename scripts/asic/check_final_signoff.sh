#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
    echo "ERROR: usage: check_final_signoff.sh FINAL_REPORT" >&2
    exit 2
fi

report=$1
if [[ ! -s "$report" ]]; then
    echo "ERROR: final sign-off report is missing or empty: $report" >&2
    exit 2
fi

required_zero_metrics=(
    "max slew violation count"
    "max fanout violation count"
    "max cap violation count"
    "setup violation count"
    "hold violation count"
)

for metric in "${required_zero_metrics[@]}"; do
    if ! rg -q "^${metric} 0$" "$report"; then
        echo "ERROR: final sign-off did not close '${metric}'" >&2
        rg -n "^${metric} " "$report" >&2 || true
        exit 1
    fi
done

if rg -q '\(VIOLATED\)' "$report"; then
    echo "ERROR: final sign-off report contains a violated timing/electrical check" >&2
    rg -n '\(VIOLATED\)' "$report" | head -20 >&2
    exit 1
fi

worst_slack=$(awk '$1 == "worst" && $2 == "slack" && $3 == "max" { print $4; exit }' "$report")
if [[ -z "$worst_slack" ]]; then
    echo "ERROR: final sign-off report has no worst-slack metric" >&2
    exit 1
fi
if ! awk -v slack="$worst_slack" 'BEGIN { exit !(slack >= 0.0) }'; then
    echo "ERROR: negative final setup slack: $worst_slack ns" >&2
    exit 1
fi

echo "PASS: zero final timing, slew, fanout, and capacitance violations"
