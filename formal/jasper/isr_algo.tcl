# JasperGold FPV: the SymbiYosys property set (../isr_props.svh) on ISR:
# control C1-C8, helper H1, and the algorithm proof A1-A3 (assume-guarantee:
# the multiplier output is a free input, and the ghost registers in
# isr_props.svh tie each product to the number it squares).
# Cross-checks the SymbiYosys results with a commercial engine.
# Run from this directory: jg -batch -tcl isr_algo.tcl
clear -all
exec awk -f ../paste_props.awk -v props=../isr_props.svh ../../rtl/ISR.sv > ISR_fv.sv
analyze -sv12 +incdir+../../rtl +define+FORMAL+FV_ALGO \
    ../../rtl/mult_stage.sv ../../rtl/mult.sv ISR_fv.sv
# JasperGold black-boxes wide *, / and % by default (WNL018), which would
# free the partial products and the f_cyc/10 schedule in H1; keep them.
elaborate -top ISR -bbox_mul 256 -bbox_div 256 -bbox_mod 256
clock clock
reset reset
# Free the multiplier result: the proof must hold for any product value.
stopat mult_product
set_prove_time_limit 1800s
set t0 [::tcl::clock::seconds]
prove -all
puts "ALGO_TIME [expr {[::tcl::clock::seconds] - $t0}]s"
report -summary -force -file isr_algo.summary
exit -force
