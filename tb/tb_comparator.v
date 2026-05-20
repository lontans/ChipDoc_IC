`timescale 1ns/1ps

module tb_comparator;

    // signals to connect to DUT (devide under test)
    reg clk, rst_n;
    reg [7:0] v_in, v_ref, hyst;
    wire fault;

    // instantiate comparator
    comparator #(.WIDTH(8)) DUT (
        .clk   ( clk   ),
        .rst_n ( rst_n ),
        .v_in  ( v_in  ),
        .v_ref ( v_ref ),
        .hyst  ( hyst  ),
        .fault ( fault )
    );

    initial clk = 0;
    always #5 clk = ~clk; // toggle every 5ns, 10ns period, 100MHz freq

    // GTKWave dependencies (waveforms)
    initial begin
        $dumpfile ( "tb_comparator.vcd" );
        $dumpvars ( 0, tb_comparator    );
    end

    initial begin
        rst_n = 1'b0; // initializing
        v_in = 8'd0;
        v_ref = 8'd0;
        hyst = 8'd0;

        // let 200 represent 400mV

        #20 rst_n = 1'b1; // releasing reset
        #10 v_ref = 8'd200; // 400mV lets say
        #10 hyst = 8'd20; // 40mV lets say

        // safe v_in vals
        #10 v_in = 8'd50;
        #10 v_in = 8'd75;
        #20 v_in = 8'd199;

        // unsafe v_in vals
        #10 v_in = 8'd200;
        #22 v_in = 8'd201;

        // v_in hasn't recovered under hyst threshold
        #10 v_in = 8'd190;
        #10 v_in = 8'd185;
        #10 v_in = 8'd180;

        // v_in recovers
        #20 v_in = 8'd179;
        #20 v_in = 8'd70;

        // quick reset force check
        #20 v_in = 8'd220;
        #25 rst_n = 1'b0;
        #20 rst_n = 1'b1;  // now this should cause fault to reassert
        #20 v_in = 8'd150;
        #20 v_in = 8'd145;

        $finish;
    end

endmodule