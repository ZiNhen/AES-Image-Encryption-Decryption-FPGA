
`timescale 1ns/1ps

module tb_aes_encryption_core();

    // 1. Khai b�o t�n hi?u Testbench
    reg          clk;
    reg          reset_n;
    reg          start_n;
    reg  [127:0] plaintext;
    reg  [127:0] key;
    wire [127:0] ciphertext;
    wire         done;

    // 2. Kh?i t?o (Instantiate) Module m� h�a AES
    aes_encryption_core dut (
        .clk(clk),
        .reset_n(reset_n),
        .start_n(start_n),
        .plaintext(plaintext),
        .key(key),
        .ciphertext(ciphertext),
        .done(done)
    );

    // 3. T?o xung Clock (Chu k? 20ns -> T?n s? 50MHz gi?ng kit DE2)
    initial begin
        clk = 0;
        forever #10 clk = ~clk; 
    end

    // 4. K?ch b?n test (Stimulus)
    initial begin
        // In ti�u ?? console
        $display("=================================================");
        $display("          TESTBENCH AES-128 ENCRYPTION CORE      ");
        $display("=================================================");

        // Kh?i t?o gi� tr? ban ??u
        reset_n   = 0;
        start_n   = 1; // K�o l�n 1 (kh�ng ho?t ??ng)
        plaintext = 128'd0;
        key       = 128'd0;

        // Gi? reset trong 30ns r?i th? ra
        #30;
        reset_n = 1;
        #20;

        // --- B?T ??U M� H�A ---
        // N?p vector chu?n c?a NIST
        plaintext = 128'h3243f6a8885a308d313198a2e0370734;
        key       = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        
        // K�ch ho?t t�n hi?u start_n (k�o xu?ng 0 trong 1 chu k? clock)
        start_n = 0;
        #20; 
        start_n = 1; // Nh? start_n l�n l?i

        $display("Dang ma hoa...");
        $display("Plaintext : %h", plaintext);
        $display("Key       : %h", key);

        // Ch? t�n hi?u done b?t l�n (D�ng @posedge ?? b?t ch�nh x�c s??n l�n)
        @(posedge done);

        // --- KI?M TRA K?T QU? ---
        $display("\nHoan thanh sau 11 chu ky clock!");
        $display("Ciphertext thuc te : %h", ciphertext);
        $display("Ciphertext NIST    : 3925841d02dc09fbdc118597196a0b32");

        if (ciphertext == 128'h3925841d02dc09fbdc118597196a0b32) begin
            $display("\n=> KET QUA: PASSED! Mach chay dung chuan 100.");
        end else begin
            $display("\n=> KET QUA: FAILED! Ban can kiem tra lai cac module to hop.");
        end

        $display("=================================================");
        $stop; // D?ng m� ph?ng
    end

endmodule