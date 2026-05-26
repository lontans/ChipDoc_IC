`timescale 1ns/1ps

module tb_wd_timer;

    // signals to connect to DUT
    reg         clk, rst_n;
    reg         edge_pulse;
    reg  [15:0] timeout_cfg;
    wire        hb_fault;

    // instantiate wd_timer
    wd_timer #(.WIDTH(16)) DUT (
        .clk         (clk),
        .rst_n       (rst_n),
        .edge_pulse  (edge_pulse),
        .timeout_cfg (timeout_cfg),
        .hb_fault    (hb_fault)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 10ns period, 100MHz

    initial begin
        $dumpfile("sim/sim_records/tb_wd_timer.vcd");
        $dumpvars(0, tb_wd_timer);
    end

    initial begin
        rst_n      = 1'b0;
        edge_pulse = 1'b0;
        timeout_cfg = 16'd10; // small timeout for simulation

        #20 rst_n = 1'b1; // release reset

        // healthy heartbeat — pulse before timeout, hb_fault stays low
        #30 edge_pulse = 1'b1;
        #10 edge_pulse = 1'b0;
        #30 edge_pulse = 1'b1; // pulse again before timeout
        #10 edge_pulse = 1'b0;
        #30 edge_pulse = 1'b1;
        #10 edge_pulse = 1'b0;
        #30;

        // missing heartbeat — no pulse, counter runs to timeout
        // hb_fault should assert after 10 cycles
        #200;

        // heartbeat resumes — edge_pulse resets counter, hb_fault clears
        edge_pulse = 1'b1;
        #10 edge_pulse = 1'b0;
        #30;

        // change timeout_cfg to longer window
        timeout_cfg = 16'd20;
        #30 edge_pulse = 1'b1;
        #10 edge_pulse = 1'b0;
        #150; // 15 cycles — under new threshold, no fault
        edge_pulse = 1'b1;
        #10 edge_pulse = 1'b0;
        #30;

        // reset during fault
        #200; // let fault assert
        rst_n = 1'b0;
        #20 rst_n = 1'b1; // hb_fault should clear
        #30;

        $finish;
    end

endmodule