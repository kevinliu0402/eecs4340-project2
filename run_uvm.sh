#!/bin/bash
# Compile and run this repo's ISR UVM testbench with VCS.
# The SVA bind is compiled too. A good run prints "UVM PASS isr".
# COV=1 ./run_uvm.sh also collects line/cond/FSM/toggle/branch coverage on
# the DUT only and writes a URG text report (urg/dashboard.txt, urg/modinfo.txt).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/kl3755_uvm/isr"
rm -rf "$OUT"
mkdir -p "$OUT"

cd "$OUT"
COV_OPTS=()
SIM_COV=()
if [ "${COV:-0}" = "1" ]; then
    echo "+tree tb_isr_uvm.dut" > cov_hier.cfg
    COV_OPTS=(-cm line+cond+fsm+tgl+branch -cm_hier cov_hier.cfg)
    SIM_COV=(-cm line+cond+fsm+tgl+branch)
fi
vcs -sverilog -full64 ${COV_OPTS[@]+"${COV_OPTS[@]}"} \
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
./simv +UVM_VERBOSITY=UVM_LOW -assert finish_maxfail=1 ${SIM_COV[@]+"${SIM_COV[@]}"} | tee sim.log
grep -q "UVM PASS isr" sim.log
grep -q "UVM_ERROR :    0" sim.log
grep -q "UVM_FATAL :    0" sim.log

if [ "${COV:-0}" = "1" ]; then
    urg -dir simv.vdb -format text -report urg > urg.log 2>&1
    echo "Coverage report: $OUT/urg"
    sed -n '1,40p' urg/dashboard.txt
fi
