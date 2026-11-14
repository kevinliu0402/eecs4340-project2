# JasperGold FPV: ISR + 8-stage multiplier, control and latency properties.
# Proves the concurrent SVA in sva/isr_mult_sva.sv (bound into ISR and mult).
# Run from this directory: jg -batch -tcl isr_control.tcl
clear -all
analyze -sv12 +incdir+../../rtl \
    ../../rtl/mult_stage.sv ../../rtl/mult.sv ../../rtl/ISR.sv \
    ../../sva/isr_mult_sva.sv
# JasperGold black-boxes wide *, / and % by default (WNL018), which would
# free the partial products and the f_cyc/10 schedule in H1; keep them.
elaborate -top ISR -bbox_mul 256 -bbox_div 256 -bbox_mod 256
clock clock
reset reset
set_prove_time_limit 900s
# Control/latency only here; the datapath checks run in isr_product.tcl and
# isr_sqrt.tcl with abstractions.
prove -property {*a_done_pulse *a_mult_latency *a_mult_start_pulse *a_done_latency *a_done_only_from_start}
report -summary -force -file isr_control.summary
exit -force
