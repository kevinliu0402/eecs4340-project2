#!/bin/bash
# Compile and run this repo's ISR and multiplier SVA testbench with VCS.
# An assertion failure stops the sim. A good run prints "SVA PASS isr".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/kl3755_sva/isr"
rm -rf "$OUT"
mkdir -p "$OUT"

cd "$OUT"
vcs -sverilog -full64 \
    -timescale=1ns/1ps \
    -assert enable_hier \
    +incdir+"${ROOT}/rtl" \
    "${ROOT}/rtl/mult_stage.sv" \
    "${ROOT}/rtl/mult.sv" \
    "${ROOT}/rtl/ISR.sv" \
    "${ROOT}/sva/isr_mult_sva.sv" \
    "${ROOT}/sva/tb_isr_sva.sv" \
    -o simv
./simv -assert finish_maxfail=1
