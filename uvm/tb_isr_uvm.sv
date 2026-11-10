// UVM testbench for the integer square root. Compile with VCS -ntb_opts uvm-1.2.
// isr_mult_sva.sv stays bound, so the pipeline delay and the r^2 check still
// run. The scoreboard repeats that numeric check on every done pulse.

import uvm_pkg::*;
`include "uvm_macros.svh"

interface isr_if (input logic clock);
    logic        reset;
    logic [63:0] value;
    logic [31:0] result;
    logic        done;
endinterface

class isr_item extends uvm_sequence_item;
    rand bit [63:0] value;
    bit      [31:0] result;
    `uvm_object_utils_begin(isr_item)
        `uvm_field_int(value,  UVM_ALL_ON)
        `uvm_field_int(result, UVM_ALL_ON)
    `uvm_object_utils_end
    function new(string name = "isr_item");
        super.new(name);
    endfunction
endclass

class isr_sequencer extends uvm_sequencer #(isr_item);
    `uvm_component_utils(isr_sequencer)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

class isr_driver extends uvm_driver #(isr_item);
    `uvm_component_utils(isr_driver)
    virtual isr_if vif;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual isr_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "isr_if was not passed to the driver")
    endfunction

    task automatic run_one(bit [63:0] v);
        int cycles;
        vif.value <= v;
        vif.reset <= 1'b1;
        repeat (3) @(posedge vif.clock);
        @(negedge vif.clock);
        vif.reset <= 1'b0;
        cycles = 0;
        forever begin
            @(posedge vif.clock);
            #1;
            if (vif.done)
                break;
            cycles++;
            if (cycles > 800)
                `uvm_fatal("ISR", $sformatf("timed out for value %0d", v))
        end
        repeat (3) @(posedge vif.clock);
    endtask

    task run_phase(uvm_phase phase);
        isr_item tr;
        vif.reset <= 1'b0;
        vif.value <= '0;
        forever begin
            seq_item_port.get_next_item(tr);
            run_one(tr.value);
            seq_item_port.item_done();
        end
    endtask
endclass

class isr_monitor extends uvm_monitor;
    `uvm_component_utils(isr_monitor)
    virtual isr_if vif;
    uvm_analysis_port #(isr_item) ap;
    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction
    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(virtual isr_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "isr_if was not passed to the monitor")
    endfunction
    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clock);
            #1;
            if (!vif.reset && vif.done) begin
                isr_item tr = isr_item::type_id::create("tr");
                tr.value  = vif.value;
                tr.result = vif.result;
                ap.write(tr);
            end
        end
    endtask
endclass

class isr_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(isr_scoreboard)
    uvm_analysis_imp #(isr_item, isr_scoreboard) imp;
    int n_done, n_mismatch;
    function new(string name, uvm_component parent);
        super.new(name, parent);
        imp = new("imp", this);
    endfunction
    function void write(isr_item tr);
        bit [127:0] res_sq, next_sq, wide_value;
        n_done++;
        res_sq     = {96'b0, tr.result} * {96'b0, tr.result};
        next_sq    = ({96'b0, tr.result} + 128'd1) * ({96'b0, tr.result} + 128'd1);
        wide_value = {64'b0, tr.value};
        if ((res_sq > wide_value) || (next_sq <= wide_value)) begin
            n_mismatch++;
            `uvm_error("ISR", $sformatf("sqrt(%0d) = %0d fails r^2 <= value < (r+1)^2",
                       tr.value, tr.result))
        end else begin
            `uvm_info("ISR", $sformatf("value %0d -> %0d", tr.value, tr.result), UVM_LOW)
        end
    endfunction
endclass

class isr_agent extends uvm_agent;
    `uvm_component_utils(isr_agent)
    isr_driver    drv;
    isr_monitor   mon;
    isr_sequencer sqr;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        drv = isr_driver::type_id::create("drv", this);
        mon = isr_monitor::type_id::create("mon", this);
        sqr = isr_sequencer::type_id::create("sqr", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass

class isr_env extends uvm_env;
    `uvm_component_utils(isr_env)
    isr_agent      agt;
    isr_scoreboard sb;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        agt = isr_agent::type_id::create("agt", this);
        sb  = isr_scoreboard::type_id::create("sb", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        agt.mon.ap.connect(sb.imp);
    endfunction
endclass

class isr_sequence extends uvm_sequence #(isr_item);
    `uvm_object_utils(isr_sequence)
    function new(string name = "isr_sequence");
        super.new(name);
    endfunction
    task automatic send_value(bit [63:0] v);
        isr_item tr = isr_item::type_id::create("tr");
        start_item(tr);
        tr.value = v;
        finish_item(tr);
    endtask
    task body();
        send_value(64'd0);
        send_value(64'd1);
        send_value(64'd2);
        send_value(64'd144);
        send_value(64'd1000);
        send_value(64'h1_0000_0000);
        send_value(64'hFFFF_FFFF_FFFF_FFFF);
    endtask
endclass

class isr_uvm_test extends uvm_test;
    `uvm_component_utils(isr_uvm_test)
    isr_env env;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        env = isr_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        isr_sequence seq = isr_sequence::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agt.sqr);
        if (env.sb.n_mismatch != 0 || env.sb.n_done != 7)
            `uvm_error("ISR", $sformatf("done=%0d mismatches=%0d", env.sb.n_done, env.sb.n_mismatch))
        else
            `uvm_info("PASS", "UVM PASS isr", UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass

module tb_isr_uvm;
    logic clock;
    isr_if vif(.clock(clock));

    ISR dut (
        .reset  (vif.reset),
        .value  (vif.value),
        .clock  (clock),
        .result (vif.result),
        .done   (vif.done)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    initial begin
        uvm_config_db#(virtual isr_if)::set(null, "*", "vif", vif);
        run_test("isr_uvm_test");
    end

    initial begin
        #5ms;
        $fatal(1, "ISR UVM test timed out");
    end
endmodule
