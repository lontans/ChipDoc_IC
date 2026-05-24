// testbench for top level module


`timescale 1ns/1ps

module tb_cd1624_top;

    // external pin signals
    reg        rst_n;
    reg        mode;
    reg        mr;
    reg        hb;
    reg        scl, sda;
    reg  [7:0] vsen_a, vsen_b;
    reg  [7:0] isen_a, isen_b;
    reg  [7:0] tsen;
    wire       health, warn, en_out;

    // instantiate top level
    cd1624_top #(
        .CLK         (100  ),
        .V_REF_OC_A  (8'd150),
        .V_REF_OC_B  (8'd150),
        .V_REF_OV_A  (8'd200),
        .V_REF_OV_B  (8'd200),
        .V_REF_UV_A  (8'd80 ),
        .V_REF_UV_B  (8'd80 ),
        .V_REF_OT    (8'd180),
        .HYST        (8'd10 ),
        .HB_TIMEOUT  (16'd20)   // small for simulation
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

    // heartbeat task — toggles hb at given period for n cycles
    task send_heartbeat;
        input integer n;
        input integer half_period;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                #(half_period) hb = ~hb;
            end
        end
    endtask

    // clear all fault inputs
    task healthy_inputs;
        begin
            vsen_a = 8'd150;   // between UV(80) and OV(200) — healthy
            vsen_b = 8'd150;
            isen_a = 8'd100;   // below OC(150) — healthy
            isen_b = 8'd100;
            tsen   = 8'd100;   // below OT(180) — healthy
        end
    endtask

    initial begin
        // initialize
        rst_n  = 1'b0;
        mode   = 1'b0;
        mr     = 1'b0;
        hb     = 1'b0;
        scl    = 1'b0;
        sda    = 1'b1;
        healthy_inputs;

        #40 rst_n = 1'b1;  // release reset
        #20;

        // ── scenario 1: normal powerup ───────────────────────────
        // all inputs healthy, HB toggling — should reach NORMAL
        // health=1, warn=0, en_out=1
        send_heartbeat(10, 20);
        #50;

        // ── scenario 2: overcurrent rail A ──────────────────────
        // isen_a crosses OC threshold — WARN then FAULT
        // warn should assert first, then en_out deasserts
        isen_a = 8'd200;   // above OC threshold of 150
        send_heartbeat(6, 20);
        #200;              // wait for debounce + warn escalation

        // clear OC — auto recover
        isen_a = 8'd100;
        #300;

        // ── scenario 3: overvoltage rail B ──────────────────────
        // immediate fault, no warn — latching
        vsen_b = 8'd220;   // above OV threshold of 200
        send_heartbeat(4, 20);
        #300;

        // OV clears — should stay in FAULT (latched)
        vsen_b = 8'd150;
        #300;

        // assert MR — should recover
        mr = 1'b1;
        #20 mr = 1'b0;
        #50;

        // ── scenario 4: undervoltage rail A ─────────────────────
        // vsen_a drops below UV threshold — WARN then FAULT
        vsen_a = 8'd50;    // below UV threshold of 80
        send_heartbeat(6, 20);
        #300;

        // voltage recovers — auto recover
        vsen_a = 8'd150;
        #300;

        // ── scenario 5: overtemperature ─────────────────────────
        // tsen crosses OT threshold — WARN then FAULT
        tsen = 8'd200;     // above OT threshold of 180
        send_heartbeat(6, 20);
        #300;

        // temperature recovers
        tsen = 8'd100;
        #400;

        // ── scenario 6: missing heartbeat ───────────────────────
        // stop toggling HB — wd_timer times out after HB_TIMEOUT=20 cycles
        // immediate FAULT, latching
        healthy_inputs;
        #500;              // well past HB_TIMEOUT of 20 cycles

        // heartbeat resumes + MR to recover
        send_heartbeat(4, 20);
        mr = 1'b1;
        #20 mr = 1'b0;
        #50;

        // ── scenario 7: multiple simultaneous faults ─────────────
        isen_a = 8'd200;   // OC
        vsen_b = 8'd50;    // UV on rail B
        send_heartbeat(6, 20);
        #200;

        isen_a = 8'd100;
        vsen_b = 8'd150;
        #400;

        // ── scenario 8: reset during fault ──────────────────────
        vsen_a = 8'd220;   // OV — immediate fault
        send_heartbeat(4, 20);
        #100;
        rst_n = 1'b0;
        #40 rst_n = 1'b1;
        vsen_a = 8'd150;
        send_heartbeat(4, 20);
        #100;

        $finish;
    end

endmodule