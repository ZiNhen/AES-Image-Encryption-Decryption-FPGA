module MasterController (
    input  wire        CLOCK_50,    // 50MHz từ kit DE2
    input  wire        reset_n,     // Nút nhấn Reset (KEY0) - Bất đồng bộ
    input  wire        btn_enc,     // Nút nhấn Mã hóa (KEY1)
    input  wire        btn_dec,     // Nút nhấn Giải mã (KEY2)
    
    // SRAM Physical Interface
    output wire [17:0] SRAM_ADDR,
    inout  wire [15:0] SRAM_DQ,
    output wire        SRAM_WE_N, SRAM_OE_N, SRAM_UB_N, SRAM_LB_N, SRAM_CE_N,
    
    // VGA Physical Interface
    output wire        VGA_HS, VGA_VS,
    output wire [9:0]  VGA_R, VGA_G, VGA_B,
    output wire        VGA_CLK, VGA_BLANK_N, VGA_SYNC_N
);

//******************************************************************************
// 1. KHAI BÁO THÔNG SỐ VÀ TÍN HIỆU TRUNG GIAN
//******************************************************************************
parameter ST_INIT     = 3'd5,  // Trạng thái tự động nạp ảnh khởi tạo từ ROM sang SRAM
          ST_IDLE     = 3'd0, 
          ST_ENCRYPT  = 3'd1, 
          ST_WAIT_DEC = 3'd2, 
          ST_DECRYPT  = 3'd3, 
          ST_DONE     = 3'd4;

parameter P_IDLE      = 2'd0, 
          P_READ      = 2'd1, 
          P_AES_WAIT  = 2'd2, 
          P_WRITE     = 2'd3;

reg [2:0] state_fsm, next_state_fsm;
reg [1:0] proc_fsm, next_proc_fsm;

reg [6:0] row_enc, row_dec;
reg [3:0] block_idx;
reg is_encrypted;

// Các bộ đếm chu kỳ xử lý chống lệch pha và timing vật lý
reg [3:0] read_cycle;   // 0 -> 9 (Chu kỳ đọc 10 bước)
reg [3:0] write_cycle;  // 0 -> 15 (Chu kỳ ghi 2 bước/pixel)

// Biến điều khiển nạp ảnh khởi tạo ban đầu từ ROM
reg [13:0] init_counter; 
wire [15:0] rom_data_out;

// Đồng bộ hóa khung hình dọc
reg vsync_d;
always @(posedge CLOCK_50 or negedge reset_n) begin
    if (!reset_n) vsync_d <= 1'b1;
    else vsync_d <= VGA_VS;
end
wire vsync_trig = vsync_d && !VGA_VS; // Xung kích hoạt đúng lúc bắt đầu Vertical Sync

wire [9:0] vga_x, vga_y;
wire vga_on;
reg clk_25;

reg [17:0] aes_addr;
reg [15:0] aes_wdata;
reg aes_we, aes_rd;

reg [127:0] aes_in;
wire [127:0] enc_out, dec_out;
reg  enc_start, dec_start;
wire enc_done, dec_done;
wire [15:0] sram_data_r;

//******************************************************************************
// 2. KHỞI TẠO CÁC MODULE IP CORES
//******************************************************************************
always @(posedge CLOCK_50 or negedge reset_n) begin
    if (!reset_n) clk_25 <= 0;
    else clk_25 <= ~clk_25;
end

vga_controller VGA_UNIT (
    .clk_25mhz(clk_25), .reset(!reset_n),
    .hsync(VGA_HS), .vsync(VGA_VS), .x_pos(vga_x), .y_pos(vga_y), .video_on(vga_on)
);

// Tránh VGA can thiệp trong lúc mạch đang tự khởi tạo nạp ảnh lúc boot
wire vga_active = vga_on && (state_fsm != ST_INIT);

sram_controller SRAM_UNIT (
    .clk(CLOCK_50), .reset(!reset_n),
    .i_addr(vga_active ? vga_addr : aes_addr),
    .i_data_write(aes_wdata),
    .i_we(!vga_active && aes_we),
    .i_rd(vga_active || (!vga_active && aes_rd)),
    .o_data_read(sram_data_r),
    .SRAM_ADDR(SRAM_ADDR), .SRAM_DQ(SRAM_DQ), .SRAM_WE_N(SRAM_WE_N),
    .SRAM_OE_N(SRAM_OE_N), .SRAM_UB_N(SRAM_UB_N), .SRAM_LB_N(SRAM_LB_N), .SRAM_CE_N(SRAM_CE_N)
);

aes_encryption_core ENC_UNIT (
    .clk(CLOCK_50), .reset_n(reset_n), .start_n(enc_start),
    .plaintext(aes_in), .key(128'h2b7e151628aed2a6abf7158809cf4f3c),
    .ciphertext(enc_out), .done(enc_done)
);

aes_decryption_core DEC_UNIT (
    .clk(CLOCK_50), .reset_n(reset_n), .start_n(dec_start),
    .ciphertext(aes_in), .key(128'h2b7e151628aed2a6abf7158809cf4f3c),
    .plaintext(dec_out), .done(dec_done)
);

// Khối ROM lưu trữ ảnh màu gốc sinh ra từ MegaWizard (.mif)
image_rom ROM_UNIT (
    .address(init_counter),
    .clock(CLOCK_50),
    .q(rom_data_out)
);

//******************************************************************************
// 3. LOGIC HIỂN THỊ VGA (3 KHUNG HÌNH TRÊN NỀN ĐEN TUYỀN)
//******************************************************************************
// Xác định tọa độ chính xác của từng khung hình để tạo mặt nạ hiển thị nền đen
wire in_frame1 = (vga_y >= 176 && vga_y < 304) && (vga_x >= 40  && vga_x < 168);
wire in_frame2 = (vga_y >= 176 && vga_y < 304) && (vga_x >= 256 && vga_x < 384) && ((vga_y-176) <= row_enc) && (state_fsm != ST_IDLE && state_fsm != ST_INIT);
wire in_frame3 = (vga_y >= 176 && vga_y < 304) && (vga_x >= 472 && vga_x < 600) && ((vga_y-176) <= row_dec) && (state_fsm == ST_DONE);

wire in_any_frame = in_frame1 || in_frame2 || in_frame3;

wire [17:0] vga_addr = (vga_y >= 176 && vga_y < 304) ? (
    (vga_x >= 40  && vga_x < 168) ? (18'h00000 + (vga_y-176)*128 + (vga_x-40)) :
    (vga_x >= 256 && vga_x < 384) ? (18'h10000 + (vga_y-176)*128 + (vga_x-256)) :
    (vga_x >= 472 && vga_x < 600) ? (18'h20000 + (vga_y-176)*128 + (vga_x-472)) : 18'd0
) : 18'd0;

assign VGA_CLK     = clk_25;
assign VGA_SYNC_N  = 1'b0;
assign VGA_BLANK_N = vga_on;

// Ép màu về đen tuyền (10'd0) khi không nằm trong bất kỳ khung hình hiển thị nào
assign VGA_R = (vga_on && in_any_frame && state_fsm != ST_INIT) ? {sram_data_r[15:11], 5'b0} : 10'd0;
assign VGA_G = (vga_on && in_any_frame && state_fsm != ST_INIT) ? {sram_data_r[10:5],  4'b0} : 10'd0;
assign VGA_B = (vga_on && in_any_frame && state_fsm != ST_INIT) ? {sram_data_r[4:0],   5'b0} : 10'd0;

//******************************************************************************
// 4. MÁY TRẠNG THÁI CHÍNH (MASTER FSM)
//******************************************************************************
always @(*) begin
    next_state_fsm = state_fsm;
    case (state_fsm)
        ST_INIT:      next_state_fsm = (init_counter == 14'd16383 && !vga_on) ? ST_IDLE : ST_INIT;
        ST_IDLE:      next_state_fsm = (!btn_enc) ? ST_ENCRYPT : ST_IDLE;
        ST_ENCRYPT:   next_state_fsm = (row_enc == 127 && proc_fsm == P_WRITE && write_cycle == 15 && block_idx == 15) ? ST_WAIT_DEC : ST_ENCRYPT;
        ST_WAIT_DEC:  next_state_fsm = (!btn_dec && is_encrypted) ? ST_DECRYPT : ST_WAIT_DEC;
        ST_DECRYPT:   next_state_fsm = (row_dec == 127 && proc_fsm == P_WRITE && write_cycle == 15 && block_idx == 15) ? ST_DONE : ST_DECRYPT;
        ST_DONE:      next_state_fsm = ST_DONE; // Chờ Reset bất đồng bộ
        default:      next_state_fsm = ST_INIT;
    endcase
end

//******************************************************************************
// 5. MÁY TRẠNG THÁI XỬ LÝ KHỐI (PROC FSM) - CHỈ CHẠY KHI VSYNC KÍCH HOẠT
//******************************************************************************
always @(*) begin
    next_proc_fsm = proc_fsm;
    case (proc_fsm)
        P_IDLE:     if ((state_fsm == ST_ENCRYPT || state_fsm == ST_DECRYPT) && vsync_trig) next_proc_fsm = P_READ;
        P_READ:     if (read_cycle == 4'd9) next_proc_fsm = P_AES_WAIT;
        P_AES_WAIT: if (enc_done || dec_done) next_proc_fsm = P_WRITE;
        P_WRITE:    if (write_cycle == 4'd15) begin
                        if (block_idx == 15) next_proc_fsm = P_IDLE;
                        else                 next_proc_fsm = P_READ;
                    end
        default:    next_proc_fsm = P_IDLE;
    endcase
end

//******************************************************************************
// 6. CẬP NHẬT TRẠNG THÁI VÀ ĐIỀU KHIỂN ĐẦU RA (XỬ LÝ ĐỒNG BỘ CHÍNH XÁC)
//******************************************************************************
always @(posedge CLOCK_50 or negedge reset_n) begin
    if (!reset_n) begin
        state_fsm <= ST_INIT;
        proc_fsm  <= P_IDLE;
        row_enc <= 0; row_dec <= 0; is_encrypted <= 0;
        block_idx <= 0;
        read_cycle <= 0; write_cycle <= 0;
        init_counter <= 0;
        aes_we <= 0; aes_rd <= 0; enc_start <= 1; dec_start <= 1;
    end begin
        state_fsm <= next_state_fsm;
        proc_fsm  <= next_proc_fsm;

        if (state_fsm == ST_INIT) begin
            // Nạp siêu tốc ROM sang SRAM trong 0.65ms khi boot máy
            aes_we <= 1'b1;
            aes_rd <= 1'b0;
            aes_addr <= {4'b0000, init_counter}; 
            aes_wdata <= rom_data_out;
            if (init_counter == 14'd16383) begin
                aes_we <= 1'b0;
            end else begin
                init_counter <= init_counter + 1'b1;
            end
        end else begin
            case (proc_fsm)
                P_IDLE: begin
                    block_idx <= 0;
                    read_cycle <= 0;
                    write_cycle <= 0;
                    aes_we <= 0;
                    aes_rd <= 0;
                end

                P_READ: begin
                    aes_rd <= 1'b1;
                    aes_we <= 1'b0;
                    
                    // Thiết lập địa chỉ sớm 2 chu kỳ để đón đầu dữ liệu phản hồi
                    if (read_cycle <= 4'd7) begin
                        aes_addr <= (state_fsm == ST_ENCRYPT ? 18'h00000 : 18'h10000) 
                                    + (state_fsm == ST_ENCRYPT ? row_enc : row_dec)*128 
                                    + block_idx*8 + read_cycle;
                    end
                    
                    // Dịch chuyển tuần tự từ chu kỳ 2 đến 9 để bù đắp 1-cycle trễ của SRAM Controller
                    if (read_cycle >= 4'd2 && read_cycle <= 4'd9) begin
                        aes_in <= {aes_in[111:0], sram_data_r};
                    end
                    
                    // Hạ chân đọc sớm tại chu kỳ 8
                    if (read_cycle == 4'd8) begin
                        aes_rd <= 1'b0;
                    end
                    
                    // Kết thúc chu kỳ đọc và kích hoạt lõi AES tương ứng
                    if (read_cycle == 4'd9) begin
                        read_cycle <= 4'd0;
                        if (state_fsm == ST_ENCRYPT) enc_start <= 1'b0; 
                        else                         dec_start <= 1'b0;
                    end else begin
                        read_cycle <= read_cycle + 1'b1;
                    end
                end

                P_AES_WAIT: begin
                    enc_start <= 1'b1; dec_start <= 1'b1;
                end

                P_WRITE: begin
                    // Chu kỳ ghi kép (2 clock/pixel): clock lẻ đưa dữ liệu ổn định, clock chẵn giật WE lên mức cao
                    if (write_cycle[0] == 1'b0) begin
                        aes_we <= 1'b0;
                        aes_addr <= (state_fsm == ST_ENCRYPT ? 18'h10000 : 18'h20000) 
                                    + (state_fsm == ST_ENCRYPT ? row_enc : row_dec)*128 
                                    + block_idx*8 + (write_cycle >> 1);
                        aes_wdata <= (state_fsm == ST_ENCRYPT) ? enc_out[127 - (write_cycle >> 1)*16 -: 16] 
                                                               : dec_out[127 - (write_cycle >> 1)*16 -: 16];
                        write_cycle <= write_cycle + 1'b1;
                    end else begin
                        aes_we <= 1'b1; // Tích cực ghi ổn định
                        write_cycle <= write_cycle + 1'b1;
                        
                        // Kiểm tra kết thúc ghi 8 pixels và chuyển khối / chuyển dòng
                        if (write_cycle == 4'd15) begin
                            write_cycle <= 4'd0;
                            aes_we <= 1'b0;
                            
                            if (block_idx == 4'd15) begin
                                block_idx <= 4'd0;
                                if (state_fsm == ST_ENCRYPT) begin
                                    if (row_enc == 7'd127) is_encrypted <= 1'b1;
                                    else                   row_enc <= row_enc + 1'b1;
                                end else begin
                                    if (row_dec < 7'd127)  row_dec <= row_dec + 1'b1;
                                end
                            end else begin
                                block_idx <= block_idx + 1'b1;
                            end
                        end
                    end
                end
            endcase
        end
    end
end

endmodule