# Copy a Verilog file, adding `include "<props>" before its last endmodule.
# Usage: awk -f paste_props.awk -v props=file.svh in.sv > out.sv
{ line[NR] = $0; if ($0 ~ /^endmodule/) last = NR }
END {
    for (i = 1; i <= NR; i++) {
        if (i == last) printf "`include \"%s\"\n", props
        print line[i]
    }
}
