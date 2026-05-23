`timescale 1ns/1ps

module tb_fault_fsm;

    // signals to connect to DUT
    reg  clk, rst_n;
    reg  oc_a, oc_b;
    reg  uv_a, uv_b;
    reg  ov_a, ov_b;
    reg  ot;
    reg  hb_fault;
    reg  mr;
    wire en_out, health, warn;

    // instantiate fault_fsm
    fault_fsm DUT (
        .clk      (clk),
        .rst_n    (rst_n),
        .oc_a     (oc_a),
        .oc_b     (oc_b),
        .uv_a     (uv_a),
        .uv_b     (uv_b),
        .ov_a     (ov_a),
        .ov_b     (ov_b),
        .ot       (ot),
        .hb_fault (hb_fault),
        .mr       (mr),
        .en_out   (en_out),
        .health   (health),
        .warn     (warn)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 10ns period, 100MHz

    initial begin
        $dumpfile("tb_fault_fsm.vcd");
        $dumpvars(0, tb_fault_fsm);
    end

    // task to clear all fault inputs cleanly
    task clear_all;
        begin
            oc_a = 0; oc_b = 0;
            uv_a = 0; uv_b = 0;
            ov_a = 0; ov_b = 0;
            ot   = 0; hb_fault = 0;
            mr   = 0;
        end
    endtask

    initial begin
        // initialize
        rst_n = 1'b0;
        clear_all;

        #20 rst_n = 1'b1;
        #20; // settle through INIT into NORMAL

        // scenario 1: normal powerup
        // should be INIT → NORMAL, en_out=1 health=1 warn=0
        #20;

        // scenario 2: OV immediate fault (latching)
        // NORMAL → FAULT immediately, no WARN
        // en_out and health should deassert, warn should assert
        #10 ov_a = 1'b1;
        #30;

        // OV clears — should stay in FAULT (latched), needs MR
        ov_a = 1'b0;
        #40;

        // assert MR — should go to RECOVERY then NORMAL
        mr = 1'b1;
        #10 mr = 1'b0;
        #20;

        // scenario 3: UV warn escalation
        // NORMAL → WARN → FAULT after 10 cycles
        // warn should assert in WARN state
        #10 uv_a = 1'b1;
        #150; // hold for 15 cycles, past warn threshold of 10

        // fault clears — auto recover (not latching)
        uv_a = 1'b0;
        #20;
        // no MR needed — should auto recover to NORMAL
        #20;

        // scenario 4: UV clears during WARN
        // should return to NORMAL without reaching FAULT
        #10 uv_b = 1'b1;
        #50; // 5 cycles — under threshold
        uv_b = 1'b0;
        #30; // should be back in NORMAL

        // scenario 5: HB fault (latching, immediate)
        // NORMAL → FAULT immediately, requires MR
        #10 hb_fault = 1'b1;
        #30;
        hb_fault = 1'b0;
        #30; // stays in FAULT without MR

        mr = 1'b1;
        #10 mr = 1'b0;
        #20; // RECOVERY → NORMAL

        // scenario 6: multiple simultaneous faults
        // OC + UV together — both warn level
        // should enter WARN then escalate to FAULT
        #10 oc_a = 1'b1;
            uv_a = 1'b1;
        #150; // escalate to FAULT
        oc_a = 1'b0;
        uv_a = 1'b0;
        #20; // auto recover
        #20;

        // scenario 7: fault during RECOVERY
        // new fault appears during RECOVERY — should drop back to FAULT
        #10 oc_b = 1'b1;
        #150; // reach FAULT
        oc_b = 1'b0;
        #10; // auto recover starts
        ov_b = 1'b1; // new immediate fault during RECOVERY
        #20;
        ov_b = 1'b0;
        #20;
        mr = 1'b1;
        #10 mr = 1'b0;
        #20;

        // scenario 8: reset during fault
        #10 ov_a = 1'b1;
        #30;
        rst_n = 1'b0; // force reset mid fault
        #20 rst_n = 1'b1;
        ov_a = 1'b0;
        #30; // should be back in INIT → NORMAL cleanly

        $finish;
    end

endmodule