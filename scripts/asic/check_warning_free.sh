#!/usr/bin/env bash
set -euo pipefail

if (( $# == 0 )); then
    echo "ERROR: check_warning_free.sh needs at least one log path" >&2
    exit 2
fi

existing_paths=()
for candidate in "$@"; do
    [[ -e "$candidate" ]] && existing_paths+=("$candidate")
done

if (( ${#existing_paths[@]} == 0 )); then
    echo "ERROR: no log path exists: $*" >&2
    exit 2
fi

# Warnings are errors. Keep this deliberately broad and case-insensitive.
# There is no global waiver file: a tool warning must be fixed at its source.
if rg --no-ignore -n -i '(^|[^[:alpha:]])warn(ing)?([^[:alpha:]]|$)|\[warn(ing)?' "${existing_paths[@]}"; then
    echo "ERROR: warning text found in ASIC logs" >&2
    exit 1
fi
