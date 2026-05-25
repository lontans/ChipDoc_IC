// testbench for top level module — includes I2C transactions
`timescale 1ns/1ps

module tb_cd1624_top;

    // external pin signals
    reg        rst_n;
    reg        mode;
    reg        mr;
    reg        hb;
    reg        scl;
    reg        sda_drive;
    wire       sda;
    reg  [7:0] vsen_a, vsen_b;
    reg  [7:0] isen_a, isen_b;
    reg  [7:0] tsen;
    wire       health, warn, en_out;

    // open drain SDA
    assign sda = (sda_drive) ? 1'b0 : 1'bz;

    // instantiate top level
    // HB_TIMEOUT large so only deliberate stops trigger it
    cd1624_top #(
        .CLK         (100   ),
        .V_REF_OC_A  (8'd150),
        .V_REF_OC_B  (8'd150),
        .V_REF_OV_A  (8'd200),
        .V_REF_OV_B  (8'd200),
        .V_REF_UV_A  (8'd80 ),
        .V_REF_UV_B  (8'd80 ),
        .V_REF_OT    (8'd180),
        .HYST        (8'd10 ),
        .HB_TIMEOUT  (16'd2000)  // 2000 cycles = 20us, large enough to survive gaps
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

    // waveform dump
    initial begin
        $dumpfile("tb_cd1624_top.vcd");
        $dumpvars(0, tb_cd1624_top);
    end

    // ─────────────────────────────────────────────
    //  I2C Tasks
    // ─────────────────────────────────────────────

    parameter I2C_HALF = 100;

    task i2c_start;
        begin
            sda_drive = 1'b0;
            scl = 1'b1;
            #(I2C_HALF);
            sda_drive = 1'b1;   // SDA falls while SCL high → START
            #(I2C_HALF);
            scl = 1'b0;
            #(I2C_HALF);
        end
    endtask

    task i2c_stop;
        begin
            sda_drive = 1'b1;
            scl = 1'b0;
            #(I2C_HALF);
            scl = 1'b1;
            #(I2C_HALF);
            sda_drive = 1'b0;   // SDA rises while SCL high → STOP
            #(I2C_HALF);
        end
    endtask

    task i2c_send_bit;
        input send_val;
        begin
            scl = 1'b0;
            sda_drive = send_val ? 1'b0 : 1'b1;  // 1=release, 0=pull low
            #(I2C_HALF);
            scl = 1'b1;
            #(I2C_HALF);
            scl = 1'b0;
            #(I2C_HALF);
        end
    endtask

    task i2c_send_byte;
        input [7:0] data;
        integer j;
        begin
            for (j = 7; j >= 0; j = j - 1)
                i2c_send_bit(data[j]);
            // ACK cycle
            sda_drive = 1'b0;
            scl = 1'b0;
            #(I2C_HALF);
            scl = 1'b1;
            #(I2C_HALF);
            scl = 1'b0;
            #(I2C_HALF);
        end
    endtask

    task i2c_write;
        input [6:0] addr;
        input [3:0] reg_a;
        input [7:0] data;
        begin
            i2c_start;
            i2c_send_byte({addr, 1'b0});
            i2c_send_byte({4'b0, reg_a});
            i2c_send_byte(data);
            i2c_stop;
            #(I2C_HALF * 4);
        end
    endtask

    // ─────────────────────────────────────────────
    //  Helper Tasks
    // ─────────────────────────────────────────────

    // send n heartbeat toggles at given half period
    task send_heartbeat;
        input integer n;
        input integer half_period;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                #(half_period) hb = ~hb;
        end
    endtask

    // keep system healthy for a period — continuous heartbeat + good inputs
    task stay_healthy;
        input integer duration_ns;
        integer pulses;
        begin
            pulses = duration_ns / 20;  // 20ns per toggle
            send_heartbeat(pulses, 10);
        end
    endtask

    task healthy_inputs;
        begin
            vsen_a = 8'd150;
            vsen_b = 8'd150;
            isen_a = 8'd100;
            isen_b = 8'd100;
            tsen   = 8'd100;
        end
    endtask
    always @(health or warn)
        $display("  t=%0t health=%b warn=%b en_out=%b", $time, health, warn, en_out);
    // ─────────────────────────────────────────────
    //  Stimulus
    // ─────────────────────────────────────────────

    initial begin
        rst_n     = 1'b0;
        mode      = 1'b0;
        mr        = 1'b0;
        hb        = 1'b0;
        scl       = 1'b0;
        sda_drive = 1'b0;
        healthy_inputs;

        #40 rst_n = 1'b1;
        #100;

        // ── scenario 1: normal powerup, analog mode ──────────────
        $display("S1: normal powerup analog mode");
        stay_healthy(2000);     // long healthy window — block 1

        // ── scenario 2: OC rail A — warn then fault ──────────────
        $display("S2: OC rail A");
        isen_a = 8'd200;
        send_heartbeat(30, 10); // keep HB alive during fault
        #200;
        isen_a = 8'd100;
        send_heartbeat(10, 10); // auto recover
        stay_healthy(2000);     // healthy window — block 2

        // ── scenario 3: OV rail B — immediate latching fault ─────
        $display("S3: OV rail B latching");
        vsen_b = 8'd220;
        send_heartbeat(10, 10);
        #300;
        vsen_b = 8'd150;
        send_heartbeat(10, 10); // still faulted — latched
        #300;
        mr = 1'b1;
        #20 mr = 1'b0;
        send_heartbeat(10, 10); // recover
        stay_healthy(2000);     // healthy window — block 3

        // ── scenario 4: switch to digital mode ───────────────────
        $display("S4: switch to digital mode");
        mode = 1'b1;
        stay_healthy(1000);

        // ── scenario 5: I2C write — lower OC threshold to 120 ────
        $display("S5: I2C write OC_THRESH_A=120");
        i2c_write(7'h48, 4'h0, 8'd120);
        stay_healthy(1000);

        // drive isen_a=130 — above new threshold 120, below old 150
        // should now trigger fault
        $display("S5b: isen_a=130 should fault with threshold=120");
        isen_a = 8'd130;
        send_heartbeat(30, 10);
        #300;
        isen_a = 8'd100;
        send_heartbeat(20, 10); // auto recover
        stay_healthy(2000);     // healthy window — block 4

        // ── scenario 6: I2C write — raise OV threshold to 240 ────
        $display("S6: I2C write OV_THRESH_A=240");
        i2c_write(7'h48, 4'h2, 8'd240);
        stay_healthy(500);

        // vsen_a=220 — above old threshold 200 but below new 240
        // should NOT fault
        $display("S6b: vsen_a=220 should NOT fault with threshold=240");
        vsen_a = 8'd220;
        stay_healthy(2000);     // stays healthy — block 5
        vsen_a = 8'd150;
        stay_healthy(500);

        // ── scenario 7: UV rail A — warn then fault ──────────────
        $display("S7: UV rail A");
        vsen_a = 8'd50;
        send_heartbeat(30, 10);
        #300;
        vsen_a = 8'd150;
        send_heartbeat(20, 10);
        stay_healthy(2000);     // healthy window — block 6

        // ── scenario 8: CFG_RESET — reload all defaults ──────────
        $display("S8: CFG_RESET");
        i2c_write(7'h48, 4'hE, 8'hFF);
        stay_healthy(500);

        // isen_a=130 should NOT fault now — threshold back to 150
        $display("S8b: isen_a=130 should NOT fault after reset");
        isen_a = 8'd130;
        stay_healthy(2000);     // stays healthy — block 7
        isen_a = 8'd100;
        stay_healthy(500);

        // ── scenario 9: missing heartbeat — deliberate ───────────
        $display("S9: missing heartbeat");
        healthy_inputs;
        #25000;  // 25us — past 20us HB_TIMEOUT
        // resume HB + MR to recover
        send_heartbeat(10, 10);
        mr = 1'b1;
        #20 mr = 1'b0;
        send_heartbeat(10, 10);
        stay_healthy(2000);     // healthy window — block 8

        // ── scenario 10: wrong I2C address — ignored ─────────────
        $display("S10: wrong address 0x49 ignored");
        i2c_write(7'h49, 4'h0, 8'd50);
        stay_healthy(1000);

        // ── scenario 11: reset during fault ──────────────────────
        $display("S11: reset during OV fault");
        vsen_a = 8'd220;
        send_heartbeat(10, 10);
        #100;
        rst_n = 1'b0;
        #40 rst_n = 1'b1;
        vsen_a = 8'd150;
        stay_healthy(2000);     // healthy window — block 9

        $display("all scenarios complete");
        $finish;
    end

endmodule