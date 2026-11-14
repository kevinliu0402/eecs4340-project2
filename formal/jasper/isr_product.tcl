# JasperGold FPV: 8-stage multiplier product (a_product in sva/isr_mult_sva.sv)
# with operands bounded to W bits, W = 8 to 32 (32 = every operand ISR uses).
# SymbiYosys needed 56 min at 12 bits and did not finish 16 (see ../VPLAN.md).
# Run from this directory: jg -batch -tcl isr_product.tcl
foreach W {8 12 16 24 32} {
    clear -all
    analyze -sv12 +incdir+../../rtl \
        ../../rtl/mult_stage.sv ../../rtl/mult.sv ../../rtl/ISR.sv \
        ../../sva/isr_mult_sva.sv
    # JasperGold black-boxes wide *, / and % by default (WNL018), which
    # would free the 8x64 partial products; keep them.
    elaborate -top mult -bbox_mul 256 -bbox_div 256 -bbox_mod 256
    clock clock
    reset reset
    assume -name op_width_$W "start |-> (mcand >> $W) == 0 && (mplier >> $W) == 0"
    set_prove_time_limit 1200s
    set t0 [::tcl::clock::seconds]
    prove -property {*a_product}
    set dt [expr {[::tcl::clock::seconds] - $t0}]
    set st [get_property_info -list status [get_property_list -include {name *a_product}]]
    puts "PRODUCT_RESULT W=$W status=$st time=${dt}s"
}
exit -force
