#!/usr/bin/env bash
set -euo pipefail
artifact=${1:?expected shared library}
max=${2:?expected target glibc version}
symbols=$(objdump -T "$artifact")
required=$(printf '%s\n' "$symbols" | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' | sed 's/GLIBC_//' | sort -V | tail -1)
[[ -n $required ]]
if [[ $(printf '%s\n' "$required" "$max" | sort -V | tail -1) != "$max" ]]; then
    echo "$artifact requires glibc $required, target provides $max" >&2
    exit 1
fi
echo "$artifact requires glibc $required (target $max)"
