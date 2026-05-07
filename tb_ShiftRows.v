`timescale 1ns/1ps

module tb_sub_shift();

    // 1. Khai báo tín hi?u
    reg  [127:0] tb_state_in;       // D? li?u ??u vào
    wire [127:0] tb_sub_out;        // D? li?u sau khi qua SubBytes
    wire [127:0] tb_shift_out;      // D? li?u sau khi qua ShiftRows

    // 2. G?i các module c?n test (DUT)
    // C?p ??u vào cho SubBytes
    SubBytes SB (
        .state_in(tb_state_in), 
        .state_out(tb_sub_out)
    );

    // L?y ??u ra c?a SubBytes làm ??u vào cho ShiftRows
    ShiftRows SR (
        .state_in(tb_sub_out), 
        .state_out(tb_shift_out)
    );

    // 3. Kh?i t?o k?ch b?n test (Stimulus)
    initial begin
        $display("=============================================================");
        $display("           TESTBENCH: SUBBYTES & SHIFTROWS (ROUND 1)         ");
        $display("=============================================================");

        // N?p vector ??u vào (L?y t? tài li?u NIST FIPS-197)
        tb_state_in = 128'h193de3bea0f4e22b9ac68d2ae9f84808;

        // ??i 10ns cho m?ch t? h?p lan truy?n tín hi?u (Propagation Delay)
        #10;

        // --- KI?M TRA KH?I SUBBYTES ---
        $display("1. KIEM TRA KHOI SUBBYTES:");
        $display("   Input State      : %h", tb_state_in);
        $display("   Output Thuc te   : %h", tb_sub_out);
        $display("   Output Ky vong   : d42711aee0bf98f1b8b45de51e415230");
        
        if (tb_sub_out == 128'hd42711aee0bf98f1b8b45de51e415230) begin
            $display("   => KET QUA       : [PASSED]");
        end else begin
            $display("   => KET QUA       : [FAILED] - Ban can kiem tra lai S-Box!");
        end

        $display("\n-------------------------------------------------------------");

        // --- KI?M TRA KH?I SHIFTROWS ---
        $display("2. KIEM TRA KHOI SHIFTROWS:");
        $display("   Input (Tu S-Box) : %h", tb_sub_out);
        $display("   Output Thuc te   : %h", tb_shift_out);
        $display("   Output Ky vong   : d4bf5d30e0b452aeb84111f11e2798e5");
        
        if (tb_shift_out == 128'hd4bf5d30e0b452aeb84111f11e2798e5) begin
            $display("   => KET QUA       : [PASSED]");
        end else begin
            $display("   => KET QUA       : [FAILED] - Ban can kiem tra lai thu tu noi day!");
        end

        $display("=============================================================");
        $stop; // D?ng mô ph?ng
    end

endmodule