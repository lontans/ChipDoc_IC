`timescale 1ns/1ps

module tb_edge_detect;

    // signals to connect to DUT
    reg  clk, rst_n;
    reg  hb_in;
    wire edge_pulse;

    // instantiate edge_detect
    edge_detect DUT (
        .clk        (clk),
        .rst_n      (rst_n),
        .hb_in      (hb_in),
        .edge_pulse (edge_pulse)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 10ns period, 100MHz

    initial begin
        $dumpfile("tb_edge_detect.vcd");
        $dumpvars(0, tb_edge_detect);
    end

    initial begin
        rst_n = 1'b0;
        hb_in = 1'b0;

        #20 rst_n = 1'b1; // release reset

        // hold low — no edge, no pulse
        #50;

        // rising edge — pulse should fire for exactly one cycle
        #10 hb_in = 1'b1;
        #30;

        // hold high — no pulse while held
        #50;

        // falling edge — pulse should fire for exactly one cycle
        #10 hb_in = 1'b0;
        #30;

        // normal square wave — pulse on every transition
        #10 hb_in = 1'b1;
        #20 hb_in = 1'b0;
        #20 hb_in = 1'b1;
        #20 hb_in = 1'b0;
        #20;

        // rapid toggle every cycle — pulse every cycle
        #10 hb_in = 1'b1;
        #10 hb_in = 1'b0;
        #10 hb_in = 1'b1;
        #10 hb_in = 1'b0;
        #20;

        // reset during active toggle — no spurious pulse on release
        #10 hb_in = 1'b1;
        #10 rst_n = 1'b0;
        #20 rst_n = 1'b1;
        #30;

        $finish;
    end

endmodule