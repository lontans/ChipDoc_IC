`timescale 1ns/1ps

module tb_debounce;

    // signals to connect to DUT
    reg  clk, rst_n;
    reg  fault_in;
    wire fault_out;

    // instantiate debounce with default parameters
    debounce #(
        .THRESHOLD(10),
        .CTR_WIDTH(4)
    ) DUT (
        .clk       (clk),
        .rst_n     (rst_n),
        .fault_in  (fault_in),
        .fault_out (fault_out)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 10ns period, 100MHz

    initial begin
        $dumpfile("sim_records/tb_debounce.vcd");
        $dumpvars(0, tb_debounce);
    end

    initial begin
        rst_n    = 1'b0;
        fault_in = 1'b0;

        #20 rst_n = 1'b1; // release reset

        // single cycle glitch — should NOT assert fault_out
        #10 fault_in = 1'b1;
        #10 fault_in = 1'b0;

        #20; // settle

        // sustained fault — should assert fault_out after THRESHOLD cycles
        #10 fault_in = 1'b1;
        #150; // hold for 15 cycles, well past threshold of 10

        // fault clears — fault_out should deassert immediately
        fault_in = 1'b0;
        #30;

        // fault asserts again briefly then clears before threshold
        #10 fault_in = 1'b1;
        #50; // 5 cycles — not enough to reach threshold
        fault_in = 1'b0;
        #30;

        // reset during active fault
        #10 fault_in = 1'b1;
        #80; // let fault_out assert
        rst_n = 1'b0; // force reset
        #20 rst_n = 1'b1; // release — fault_out should be 0
        fault_in = 1'b0;
        #30;

        $finish;
    end

endmodule