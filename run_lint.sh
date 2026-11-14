#!/bin/bash
# Lint the ISR and multiplier RTL with Verilator (-Wall). Exits non-zero on
# any warning that is not waived in lint.vlt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
verilator --lint-only -Wall -I"${ROOT}/rtl" --top-module ISR \
    "${ROOT}/lint.vlt" \
    "${ROOT}/rtl/mult_stage.sv" "${ROOT}/rtl/mult.sv" "${ROOT}/rtl/ISR.sv"
echo "LINT CLEAN isr"
