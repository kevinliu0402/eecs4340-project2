# Formal verification for the Project 2 ISR and multiplier (SymbiYosys).
# Needs yosys, sby, yices, bitwuzla and python3 on PATH; the YosysHQ
# OSS CAD Suite has all but python3.
#
#   make             every quick check (about 2 minutes) and a summary
#   make control     one ISR task (also: algo, cover, deep_algo)
#   make mult        multiplier: control, and product with 8-bit operands
#   make mult_prod12 multiplier product with 12-bit operands (about 1 hour)
#   make mutants     inject 8 bugs into ISR; each must be caught

RTL := ../rtl

ISR_TASKS := control algo cover deep_algo

.PHONY: all $(ISR_TASKS) mult mult_prod12 mutants summary clean
all: $(ISR_TASKS) mult mutants summary

# Paste the property file into a copy of the RTL, just before the last endmodule.
build/ISR_fv.sv: $(RTL)/ISR.sv isr_props.svh
	@mkdir -p build
	awk -f paste_props.awk -v props=isr_props.svh $< > $@

# Yosys sizes SHIFT'('b0) as 32 bits inside a concatenation (VCS, Icarus and
# Verilator use SHIFT bits, as the LRM says), which shifts mcand by 32 instead
# of 8. The formal copy spells the same zeros as {SHIFT{1'b0}}.
build/mult_stage.sv: $(RTL)/mult_stage.sv
	@mkdir -p build
	sed "s/SHIFT'('b0)/{SHIFT{1'b0}}/g" $< > $@

build/mult_fv.sv: $(RTL)/mult.sv mult_props.svh
	@mkdir -p build
	awk -f paste_props.awk -v props=mult_props.svh $< > $@

$(ISR_TASKS): build/ISR_fv.sv build/mult_stage.sv
	sby -f isr.sby $@

mult: build/mult_fv.sv build/mult_stage.sv
	sby -f mult.sby ctrl prod8

mult_prod12: build/mult_fv.sv build/mult_stage.sv
	sby -f mult.sby prod12

mutants: build/ISR_fv.sv build/mult_stage.sv
	./run_mutants.sh | tee mutants_report.txt

summary:
	@for d in isr_* mult_*; do [ -f $$d/status ] && printf '%-16s %s\n' $$d "$$(cut -d' ' -f1 $$d/status)"; done; true

clean:
	rm -rf build isr_control isr_algo isr_cover isr_deep_algo mult_ctrl mult_prod8 mult_prod12 mutants_out
