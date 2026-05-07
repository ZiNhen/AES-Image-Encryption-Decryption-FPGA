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
parameter ST_IDLE     = 3'd0, 
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
reg [2:0] pixel_idx;
reg is_encrypted;

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

sram_controller SRAM_UNIT (
    .clk(CLOCK_50), .reset(!reset_n),
    .i_addr(vga_on ? vga_addr : aes_addr),
    .i_data_write(aes_wdata),
    .i_we(!vga_on && aes_we),
    .i_rd(vga_on || (!vga_on && aes_rd)),
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

//******************************************************************************
// 3. LOGIC HIỂN THỊ VGA (3 KHUNG HÌNH)
//******************************************************************************
wire [17:0] vga_addr = (vga_y >= 176 && vga_y < 304) ? (
    (vga_x >= 40  && vga_x < 168) ? (18'h00000 + (vga_y-176)*128 + (vga_x-40)) :
    (vga_x >= 256 && vga_x < 384 && (vga_y-176) <= row_enc && state_fsm != ST_IDLE) ? (18'h10000 + (vga_y-176)*128 + (vga_x-256)) :
    (vga_x >= 472 && vga_x < 600 && (vga_y-176) <= row_dec && state_fsm == ST_DONE) ? (18'h20000 + (vga_y-176)*128 + (vga_x-472)) : 18'd0
) : 18'd0;

assign VGA_CLK     = clk_25;
assign VGA_SYNC_N  = 1'b0;
assign VGA_BLANK_N = vga_on;
assign VGA_R = vga_on ? {sram_data_r[15:11], 5'b0} : 10'd0;
assign VGA_G = vga_on ? {sram_data_r[10:5],  4'b0} : 10'd0;
assign VGA_B = vga_on ? {sram_data_r[4:0],   5'b0} : 10'd0;

//******************************************************************************
// 4. MÁY TRẠNG THÁI CHÍNH (MASTER FSM)
//******************************************************************************
always @(*) begin
    next_state_fsm = state_fsm;
    case (state_fsm)
        ST_IDLE:      next_state_fsm = (!btn_enc) ? ST_ENCRYPT : ST_IDLE;
        ST_ENCRYPT:   next_state_fsm = (row_enc == 127 && proc_fsm == P_WRITE && pixel_idx == 7 && block_idx == 15) ? ST_WAIT_DEC : ST_ENCRYPT;
        ST_WAIT_DEC:  next_state_fsm = (!btn_dec && is_encrypted) ? ST_DECRYPT : ST_WAIT_DEC;
        ST_DECRYPT:   next_state_fsm = (row_dec == 127 && proc_fsm == P_WRITE && pixel_idx == 7 && block_idx == 15) ? ST_DONE : ST_DECRYPT;
        ST_DONE:      next_state_fsm = ST_DONE; // Chờ Reset bất đồng bộ
        default:      next_state_fsm = ST_IDLE;
    endcase
end

//******************************************************************************
// 5. MÁY TRẠNG THÁI XỬ LÝ KHỐI (PROC FSM)
//******************************************************************************
always @(*) begin
    next_proc_fsm = proc_fsm;
    case (proc_fsm)
        P_IDLE:     if (state_fsm == ST_ENCRYPT || state_fsm == ST_DECRYPT) next_proc_fsm = P_READ;
        P_READ:     if (pixel_idx == 7 && !vga_on) next_proc_fsm = P_AES_WAIT;
        P_AES_WAIT: if (enc_done || dec_done) next_proc_fsm = P_WRITE;
        P_WRITE:    if (pixel_idx == 7 && !vga_on) next_proc_fsm = (block_idx == 15) ? P_IDLE : P_READ;
        default:    next_proc_fsm = P_IDLE;
    endcase
end

//******************************************************************************
// 6. CẬP NHẬT TRẠNG THÁI VÀ ĐIỀU KHIỂN ĐẦU RA
//******************************************************************************
always @(posedge CLOCK_50 or negedge reset_n) begin
    if (!reset_n) begin
        state_fsm <= ST_IDLE;
        proc_fsm  <= P_IDLE;
        row_enc <= 0; row_dec <= 0; is_encrypted <= 0;
        block_idx <= 0; pixel_idx <= 0;
        aes_we <= 0; aes_rd <= 0; enc_start <= 1; dec_start <= 1;
    end else begin
        state_fsm <= next_state_fsm;
        proc_fsm  <= next_proc_fsm;

        case (proc_fsm)
            P_IDLE: begin
                pixel_idx <= 0;
                block_idx <= 0;
                aes_we <= 0;
                aes_rd <= 0;
            end

            P_READ: begin
                if (!vga_on) begin
                    aes_rd <= 1;
                    aes_addr <= (state_fsm == ST_ENCRYPT ? 18'h00000 : 18'h10000) + (state_fsm == ST_ENCRYPT ? row_enc : row_dec)*128 + block_idx*8 + pixel_idx;
                    aes_in <= {aes_in[111:0], sram_data_r};
                    if (pixel_idx == 7) begin
                        aes_rd <= 0;
                        pixel_idx <= 0;
                        if (state_fsm == ST_ENCRYPT) enc_start <= 0; else dec_start <= 0;
                    end else pixel_idx <= pixel_idx + 1;
                end
            end

            P_AES_WAIT: begin
                enc_start <= 1; dec_start <= 1;
            end

            P_WRITE: begin
                if (!vga_on) begin
                    aes_we <= 1;
                    aes_addr <= (state_fsm == ST_ENCRYPT ? 18'h10000 : 18'h20000) + (state_fsm == ST_ENCRYPT ? row_enc : row_dec)*128 + block_idx*8 + pixel_idx;
                    aes_wdata <= (state_fsm == ST_ENCRYPT) ? enc_out[127-pixel_idx*16 -: 16] : dec_out[127-pixel_idx*16 -: 16];
                    if (pixel_idx == 7) begin
                        aes_we <= 0;
                        pixel_idx <= 0;
                        if (block_idx == 15) begin
                            block_idx <= 0;
                            if (state_fsm == ST_ENCRYPT) begin
                                if (row_enc == 127) is_encrypted <= 1;
                                else row_enc <= row_enc + 1;
                            end else begin
                                if (row_dec < 127) row_dec <= row_dec + 1;
                            end
                        end else block_idx <= block_idx + 1;
                    end else pixel_idx <= pixel_idx + 1;
                end
            end
        endcase
    end
end

endmodule