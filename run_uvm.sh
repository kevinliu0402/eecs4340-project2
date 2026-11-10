#!/bin/bash
# Compile and run this repo's ISR UVM testbench with VCS.
# The SVA bind is compiled too. A good run prints "UVM PASS isr".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/kl3755_uvm/isr"
rm -rf "$OUT"
mkdir -p "$OUT"

cd "$OUT"
vcs -sverilog -full64 \
    -ntb_opts uvm-1.2 \
    -timescale=1ns/1ps \
    -assert enable_hier \
    +incdir+"${ROOT}/rtl" \
    "${ROOT}/rtl/mult_stage.sv" \
    "${ROOT}/rtl/mult.sv" \
    "${ROOT}/rtl/ISR.sv" \
    "${ROOT}/sva/isr_mult_sva.sv" \
    "${ROOT}/uvm/tb_isr_uvm.sv" \
    -o simv
./simv +UVM_VERBOSITY=UVM_LOW -assert finish_maxfail=1 | tee sim.log
grep -q "UVM PASS isr" sim.log
grep -q "UVM_ERROR :    0" sim.log
grep -q "UVM_FATAL :    0" sim.log
