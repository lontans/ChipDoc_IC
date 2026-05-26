// CD1624 analog mode testbench
// No I2C — just verify fault detection, warn escalation,
// latching, recovery, and health signal behavior
`timescale 1ns/1ps

module tb_cd1624_top;

    reg        rst_n;
    reg        mode;
    reg        mr;
    reg        hb;
    reg        scl; 
    wire       sda;
    reg  [7:0] vsen_a, vsen_b;
    reg  [7:0] isen_a, isen_b;
    reg  [7:0] tsen;
    wire       health, warn, en_out;

    assign sda = 1'b1;

    cd1624_top #(
        .CLK        (100   ),
        .V_REF_OC_A (8'd150),
        .V_REF_OC_B (8'd150),
        .V_REF_OV_A (8'd200),
        .V_REF_OV_B (8'd200),
        .V_REF_UV_A (8'd80 ),
        .V_REF_UV_B (8'd80 ),
        .V_REF_OT   (8'd180),
        .HYST       (8'd10 ),
        .HB_TIMEOUT (16'd500)
    ) DUT (
        .rst_n  (rst_n ),
        .mode   (mode  ),
        .mr     (mr    ),
        .hb     (hb    ),
        .scl    (scl   ),
        .sda    (sda   ),
        .vsen_a (vsen_a),
        .vsen_b (vsen_b),
        .isen_a (isen_a),
        .isen_b (isen_b),
        .tsen   (tsen  ),
        .health (health),
        .warn   (warn  ),
        .en_out (en_out)
    );

    initial begin
        $dumpfile("sim_records/tb_cd1624_top.vcd");
        $dumpvars(0, tb_cd1624_top);
    end

    always @(health or warn or en_out)
        $display("  t=%0t health=%b warn=%b en_out=%b",
                 $time, health, warn, en_out);

    task keep_alive;
        input integer duration_ns;
        integer i;
        begin
            for (i = 0; i < duration_ns/10; i = i + 1)
                #10 hb = ~hb;
        end
    endtask

    task send_hb;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                #10 hb = ~hb;
        end
    endtask

    task healthy;
        begin
            vsen_a = 8'd150;
            vsen_b = 8'd150;
            isen_a = 8'd100;
            isen_b = 8'd100;
            tsen   = 8'd100;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        mode  = 1'b0;
        mr    = 1'b0;
        hb    = 1'b0;
        scl   = 1'b0;
        healthy;
        #40 rst_n = 1'b1;
        #50;

        $display("\n1. normal powerup");
        keep_alive(3000);

        $display("\n2. OC rail A warn then fault auto-recover");
        isen_a = 8'd200;
        keep_alive(2000);
        isen_a = 8'd100;
        keep_alive(3000);

        $display("\n3. OC rail B warn then fault auto-recover");
        isen_b = 8'd200;
        keep_alive(2000);
        isen_b = 8'd100;
        keep_alive(3000);

        $display("\n4. OV rail A immediate latching");
        vsen_a = 8'd220;
        keep_alive(1000);
        vsen_a = 8'd150;
        keep_alive(1000);
        mr = 1'b1; #20 mr = 1'b0;
        keep_alive(3000);

        $display("\n5. OV rail B immediate latching");
        vsen_b = 8'd220;
        keep_alive(1000);
        vsen_b = 8'd150;
        keep_alive(1000);
        mr = 1'b1; #20 mr = 1'b0;
        keep_alive(3000);

        $display("\n6. UV rail A warn then fault auto-recover");
        vsen_a = 8'd50;
        keep_alive(2000);
        vsen_a = 8'd150;
        keep_alive(3000);

        $display("\n7. UV rail B warn then fault auto-recover");
        vsen_b = 8'd50;
        keep_alive(2000);
        vsen_b = 8'd150;
        keep_alive(3000);

        $display("\n8. OT warn then fault auto-recover");
        tsen = 8'd200;
        keep_alive(2000);
        tsen = 8'd100;
        keep_alive(3000);

        $display("\n9. missing heartbeat latching");
        healthy;
        #8000;
        send_hb(10);
        mr = 1'b1; #20 mr = 1'b0;
        keep_alive(3000);

        $display("\n10. OC_A + UV_B simultaneous");
        isen_a = 8'd200;
        vsen_b = 8'd50;
        keep_alive(2000);
        isen_a = 8'd100;
        vsen_b = 8'd150;
        keep_alive(3000);

        $display("\n11. fault during recovery");
        isen_a = 8'd200;
        keep_alive(2000);
        isen_a = 8'd100;
        #50;
        vsen_a = 8'd220;
        keep_alive(1000);
        vsen_a = 8'd150;
        keep_alive(500);
        mr = 1'b1; #20 mr = 1'b0;
        keep_alive(3000);

        $display("\n12. reset during fault");
        vsen_a = 8'd220;
        keep_alive(500);
        rst_n = 1'b0;
        #40 rst_n = 1'b1;
        vsen_a = 8'd150;
        keep_alive(3000);

        $display("\ndone — expect 12 healthy blocks");
        $finish;
    end

endmodule