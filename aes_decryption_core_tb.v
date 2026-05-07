
`timescale 1ns/1ps

module tb_aes_decryption_core();

    // 1. Khai báo tín hiệu Testbench
    reg          clk;
    reg          reset_n;
    reg          start_n;
    reg  [127:0] ciphertext;
    reg  [127:0] key;
    wire [127:0] plaintext;
    wire         done;

    // 2. Khởi tạo (Instantiate) Module giải mã AES (DUT)
    aes_decryption_core dut (
        .clk(clk),
        .reset_n(reset_n),
        .start_n(start_n),
        .ciphertext(ciphertext),
        .key(key),
        .plaintext(plaintext),
        .done(done)
    );

    // 3. Tạo xung Clock (Chu kỳ 20ns -> Tần số 50MHz giống kit DE2)
    initial begin
        clk = 0;
        forever #10 clk = ~clk; 
    end

    // 4. Kịch bản test (Stimulus)
    initial begin
        // In tiêu đề console
        $display("=================================================");
        $display("          TESTBENCH AES-128 DECRYPTION CORE      ");
        $display("=================================================");

        // Khởi tạo giá trị ban đầu (Reset toàn hệ thống)
        reset_n    = 0;
        start_n    = 1; // Kéo lên mức cao (IDLE)
        ciphertext = 128'd0;
        key        = 128'd0;

        // Giữ reset trong 30ns rồi thả ra (tương đương 1.5 chu kỳ xung)
        #30;
        reset_n = 1;
        #20;

        // --- BẮT ĐẦU QUÁ TRÌNH GIẢI MÃ ---
        // Nạp vector mã hóa chuẩn của NIST
        ciphertext = 128'h3925841d02dc09fbdc118597196a0b32;
        key        = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        
        // Kích hoạt tín hiệu start_n (kéo xuống 0 trong 1 chu kỳ clock)
        start_n = 0;
        #20; 
        start_n = 1; // Nhả start_n lên lại để mạch tự chạy

        $display("Dang khoi tao khoa K10 va Giai ma...");
        $display("Ciphertext input : %h", ciphertext);
        $display("Key input        : %h", key);

        // Chờ tín hiệu done bật lên mức 1 (Bắt sườn lên của cờ done)
        // Mạch của bạn sẽ mất khoảng 21 chu kỳ clock cho thao tác này
        @(posedge done);

        // --- KIỂM TRA KẾT QUẢ TỰ ĐỘNG ---
        $display("\nHoan thanh giai ma!");
        $display("Plaintext thuc te : %h", plaintext);
        $display("Plaintext ky vong : 3243f6a8885a308d313198a2e0370734");

        if (plaintext == 128'h3243f6a8885a308d313198a2e0370734) begin
            $display("\n=> KET QUA: PASSED! Mach hoat dong chinh xac 100.");
        end else begin
            $display("\n=> KET QUA: FAILED! Ban can kiem tra lai cac module InvMixColumns hoac InvSubBytes.");
        end

        $display("=================================================");
        $stop; // Dừng mô phỏng
    end

endmodule