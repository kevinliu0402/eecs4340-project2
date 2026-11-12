#!/usr/bin/env bash
# Mutation check for the ISR properties. For each line of mutants.txt:
#   1. inject the bug into a copy of rtl/ISR.sv
#   2. run the control and algo proofs; at least one must stop passing
#   3. find a concrete failing trace, trying in order:
#        the proof's own base case, the 40-cycle deep_algo BMC, and a
#        340-cycle Yosys simulation with value = 1001 (sim_top.sv)
# Prints one line per mutant and exits non-zero if any mutant survives.
set -uo pipefail
cd "$(dirname "$0")"

OUT=mutants_out
mkdir -p "$OUT"
make -s build/mult_stage.sv build/ISR_fv.sv
survived=0

# Name of the property at isr_props.svh:<line> (e.g. "C2"), from the nearest
# "// X<n>:" comment above it.
prop_name() {
    awk -v n="$1" 'NR <= n && match($0, /\/\/ [ACH][0-9]+[ :]/) {
        p = substr($0, RSTART + 3, RLENGTH - 4) } END { print p }' isr_props.svh
}

# Simulate one ISR_fv.sv for 340 cycles with every property checked.
sim_run() {  # $1 = ISR_fv.sv to simulate, $2 = log file
    yosys -q -p "read_verilog -formal -sv -D FV_ALGO -Ibuild -I. -I../rtl \
        build/mult_stage.sv ../rtl/mult.sv $1 sim_top.sv; prep -top sim_top; flatten; \
        async2sync; chformal -lower; \
        sim -clock clock -reset reset -rstlen 1 -n 340 -zinit -assert" > "$2" 2>&1
}

# The unmodified design must pass the same simulation.
if ! sim_run build/ISR_fv.sv "$OUT/sim_original.log"; then
    echo "the unmodified ISR fails the simulation check; see $OUT/sim_original.log"
    exit 2
fi

printf '%-3s %-15s %-17s %-5s %s\n' id proof trace prop "injected bug"
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    id=$(printf '%s' "$line" | awk -F'¦' '{gsub(/^ +| +$/, "", $1); print $1}')
    desc=$(printf '%s' "$line" | awk -F'¦' '{gsub(/^ +| +$/, "", $2); print $2}')
    dir="$OUT/$id"
    mkdir -p "$dir"

    # Apply the mutation (literal text) and check it matched exactly once.
    if ! LINE="$line" python3 - ../rtl/ISR.sv "$dir/ISR.sv" <<'EOF'
import os, sys
_, _, find, repl = [f.strip().replace("\\n", "\n") for f in os.environ["LINE"].split("¦")]
src = open(sys.argv[1]).read()
if src.count(find) != 1:
    sys.exit(f"pattern found {src.count(find)} times: {find!r}")
open(sys.argv[2], "w").write(src.replace(find, repl))
EOF
    then
        printf '%-3s %-15s %-17s %-5s %s\n' "$id" BADPATTERN - - "$desc"
        survived=1
        continue
    fi

    awk -f paste_props.awk -v props=isr_props.svh "$dir/ISR.sv" > "$dir/ISR_fv.sv"
    sed -e 's|^\.\./rtl/|../../../rtl/|' \
        -e 's|^build/ISR_fv.sv|ISR_fv.sv|' \
        -e 's|^build/mult_stage.sv|../../build/mult_stage.sv|' \
        -e 's|^isr_props.svh|../../isr_props.svh|' isr.sby > "$dir/isr.sby"

    # 1. Proofs. FAIL = base case found a trace; UNKNOWN = induction broke.
    proof=pass; trace=none; line_no=""
    for t in control algo; do
        (cd "$dir" && sby -f isr.sby "$t" > "sby_$t.log" 2>&1)
        st=$(cut -d' ' -f1 "$dir/isr_$t/status" 2>/dev/null || echo ERROR)
        if [[ "$st" == FAIL ]]; then
            proof="$t:FAIL"; trace="$t-basecase"
            line_no=$(grep -oE 'isr_props.svh:[0-9]+' "$dir/sby_$t.log" | head -1 | cut -d: -f2)
            break
        elif [[ "$st" != PASS && "$proof" == pass ]]; then
            proof="$t:$st"
        fi
    done

    # 2. Short BMC with every property asserted.
    if [[ "$trace" == none && "$proof" != pass ]]; then
        (cd "$dir" && sby -f isr.sby deep_algo > sby_deep_algo.log 2>&1)
        if [[ "$(cut -d' ' -f1 "$dir/isr_deep_algo/status" 2>/dev/null)" == FAIL ]]; then
            trace=bmc40
            line_no=$(grep -oE 'isr_props.svh:[0-9]+' "$dir/sby_deep_algo.log" | head -1 | cut -d: -f2)
        fi
    fi

    # 3. Full-length concrete run.
    if [[ "$trace" == none && "$proof" != pass ]]; then
        if ! sim_run "$dir/ISR_fv.sv" "$dir/sim.log"; then
            line_no=$(grep -oE 'isr_props.svh:[0-9]+' "$dir/sim.log" | head -1 | cut -d: -f2)
            [[ -n "$line_no" ]] && trace=sim340
        fi
    fi

    [[ "$proof" == pass ]] && survived=1
    name="-"
    [[ -n "$line_no" ]] && name=$(prop_name "$line_no")
    printf '%-3s %-15s %-17s %-5s %s\n' "$id" "$proof" "$trace" "$name" "$desc"
done < mutants.txt

exit $survived
