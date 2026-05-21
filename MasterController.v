module MasterController (
    input  wire        CLOCK_50,
    input  wire        reset_n,
    input  wire        btn_enc,
    input  wire        btn_dec,

    // SRAM
    output wire [17:0] SRAM_ADDR,
    inout  wire [15:0] SRAM_DQ,
    output wire        SRAM_WE_N,
    output wire        SRAM_OE_N,
    output wire        SRAM_UB_N,
    output wire        SRAM_LB_N,
    output wire        SRAM_CE_N,

    // VGA
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire [9:0]  VGA_R,
    output wire [9:0]  VGA_G,
    output wire [9:0]  VGA_B,
    output wire        VGA_CLK,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N
);

//=============================================================================
// MASTER FSM
//=============================================================================
parameter ST_IDLE     = 3'd0;
parameter ST_ENCRYPT  = 3'd1;
parameter ST_WAIT_DEC = 3'd2;
parameter ST_DECRYPT  = 3'd3;
parameter ST_DONE     = 3'd4;
parameter ST_INIT     = 3'd5;

//=============================================================================
// PROC FSM
//=============================================================================
parameter P_IDLE      = 3'd0;
parameter P_READ_REQ  = 3'd1;
parameter P_READ_WAIT = 3'd2;
parameter P_AES_WAIT  = 3'd3;
parameter P_WRITE     = 3'd4;
parameter P_NEXT      = 3'd5;

//=============================================================================
// REG/WIRE
//=============================================================================
reg [2:0] state_fsm, next_state_fsm;
reg [2:0] proc_fsm,  next_proc_fsm;

reg [6:0] row_enc;
reg [6:0] row_dec;

reg [3:0] block_idx;
reg [2:0] pixel_idx;

reg is_encrypted;

reg [13:0] init_counter;

wire [15:0] rom_data_out;

wire [9:0] vga_x;
wire [9:0] vga_y;
wire       vga_on;

reg clk_25;

// SRAM control
reg [17:0] aes_addr;
reg [15:0] aes_wdata;
reg aes_we;
reg aes_rd;

wire [15:0] sram_data_r;
reg  [15:0] sram_data_pipe;

// AES
reg  [127:0] aes_in;

wire [127:0] enc_out;
wire [127:0] dec_out;

reg  enc_start;
reg  dec_start;

wire enc_done;
wire dec_done;

//=============================================================================
// VGA SAFE WINDOW
//=============================================================================
wire v_blank;
assign v_blank = (vga_y >= 10'd480);

wire aes_window;
assign aes_window =
    ((state_fsm == ST_INIT) ||
     (state_fsm == ST_ENCRYPT) ||
     (state_fsm == ST_DECRYPT))
     && v_blank;

//=============================================================================
// 25MHz CLOCK
//=============================================================================
always @(posedge CLOCK_50 or negedge reset_n) begin
    if(!reset_n)
        clk_25 <= 1'b0;
    else
        clk_25 <= ~clk_25;
end

//=============================================================================
// VGA CONTROLLER
//=============================================================================
vga_controller VGA_UNIT (
    .clk_25mhz(clk_25),
    .reset(!reset_n),

    .hsync(VGA_HS),
    .vsync(VGA_VS),

    .x_pos(vga_x),
    .y_pos(vga_y),

    .video_on(vga_on)
);

//=============================================================================
// VGA ADDRESSING
//=============================================================================
wire [17:0] vga_addr;

assign vga_addr =
(vga_y >= 176 && vga_y < 304) ?

(
    (vga_x >= 40 && vga_x < 168) ?

        (18'h00000 +
        (vga_y - 176)*128 +
        (vga_x - 40))

    :

    (vga_x >= 256 && vga_x < 384 &&
     (vga_y - 176) <= row_enc &&
     state_fsm != ST_IDLE &&
     state_fsm != ST_INIT) ?

        (18'h10000 +
        (vga_y - 176)*128 +
        (vga_x - 256))

    :

    (vga_x >= 472 && vga_x < 600 &&
     (vga_y - 176) <= row_dec &&
     state_fsm == ST_DONE) ?

        (18'h20000 +
        (vga_y - 176)*128 +
        (vga_x - 472))

    :

    18'd0
)

:

18'd0;

//=============================================================================
// SRAM CONTROLLER
//=============================================================================
sram_controller SRAM_UNIT (

    .clk(CLOCK_50),
    .reset(!reset_n),

    .i_addr(aes_window ? aes_addr : vga_addr),

    .i_data_write(aes_wdata),

    .i_we(aes_window && aes_we),

    .i_rd(aes_window ? aes_rd : 1'b1),

    .o_data_read(sram_data_r),

    .SRAM_ADDR(SRAM_ADDR),
    .SRAM_DQ(SRAM_DQ),

    .SRAM_WE_N(SRAM_WE_N),
    .SRAM_OE_N(SRAM_OE_N),
    .SRAM_UB_N(SRAM_UB_N),
    .SRAM_LB_N(SRAM_LB_N),
    .SRAM_CE_N(SRAM_CE_N)
);

//=============================================================================
// AES ENCRYPTION
//=============================================================================
aes_encryption_core ENC_UNIT (
    .clk(CLOCK_50),
    .reset_n(reset_n),

    .start_n(enc_start),

    .plaintext(aes_in),

    .key(128'h2b7e151628aed2a6abf7158809cf4f3c),

    .ciphertext(enc_out),

    .done(enc_done)
);

//=============================================================================
// AES DECRYPTION
//=============================================================================
aes_decryption_core DEC_UNIT (
    .clk(CLOCK_50),
    .reset_n(reset_n),

    .start_n(dec_start),

    .ciphertext(aes_in),

    .key(128'h2b7e151628aed2a6abf7158809cf4f3c),

    .plaintext(dec_out),

    .done(dec_done)
);

//=============================================================================
// IMAGE ROM
//=============================================================================
image_rom ROM_UNIT (
    .address(init_counter),
    .clock(CLOCK_50),
    .q(rom_data_out)
);

//=============================================================================
// SRAM READ PIPELINE
//=============================================================================
always @(posedge CLOCK_50) begin
    sram_data_pipe <= sram_data_r;
end

//=============================================================================
// VGA OUTPUT
//=============================================================================
assign VGA_CLK     = clk_25;
assign VGA_SYNC_N  = 1'b0;
assign VGA_BLANK_N = vga_on;

assign VGA_R =
    vga_on ?
    {sram_data_r[15:11], 5'b0} :
    10'd0;

assign VGA_G =
    vga_on ?
    {sram_data_r[10:5], 4'b0} :
    10'd0;

assign VGA_B =
    vga_on ?
    {sram_data_r[4:0], 5'b0} :
    10'd0;

//=============================================================================
// MASTER FSM COMBINATIONAL
//=============================================================================
always @(*) begin

    next_state_fsm = state_fsm;

    case(state_fsm)

        ST_INIT:
            if(init_counter == 14'd16383)
                next_state_fsm = ST_IDLE;

        ST_IDLE:
            if(!btn_enc)
                next_state_fsm = ST_ENCRYPT;

        ST_ENCRYPT:
            if(row_enc == 7'd127 &&
               block_idx == 4'd15 &&
               proc_fsm == P_NEXT)
                next_state_fsm = ST_WAIT_DEC;

        ST_WAIT_DEC:
            if(!btn_dec && is_encrypted)
                next_state_fsm = ST_DECRYPT;

        ST_DECRYPT:
            if(row_dec == 7'd127 &&
               block_idx == 4'd15 &&
               proc_fsm == P_NEXT)
                next_state_fsm = ST_DONE;

        ST_DONE:
            next_state_fsm = ST_DONE;

        default:
            next_state_fsm = ST_INIT;

    endcase
end

//=============================================================================
// PROC FSM COMBINATIONAL
//=============================================================================
always @(*) begin

    next_proc_fsm = proc_fsm;

    case(proc_fsm)

        P_IDLE:
            if((state_fsm == ST_ENCRYPT ||
                state_fsm == ST_DECRYPT) &&
                aes_window)
                next_proc_fsm = P_READ_REQ;

        P_READ_REQ:
            next_proc_fsm = P_READ_WAIT;

        P_READ_WAIT:
            if(pixel_idx == 3'd7)
                next_proc_fsm = P_AES_WAIT;
            else
                next_proc_fsm = P_READ_REQ;

        P_AES_WAIT:
            if((state_fsm == ST_ENCRYPT && enc_done) ||
               (state_fsm == ST_DECRYPT && dec_done))
                next_proc_fsm = P_WRITE;

        P_WRITE:
            if(pixel_idx == 3'd7)
                next_proc_fsm = P_NEXT;

        P_NEXT:
            if(block_idx == 4'd15)
                next_proc_fsm = P_IDLE;
            else
                next_proc_fsm = P_READ_REQ;

        default:
            next_proc_fsm = P_IDLE;

    endcase
end

//=============================================================================
// MAIN SEQUENTIAL
//=============================================================================
always @(posedge CLOCK_50 or negedge reset_n) begin

    if(!reset_n) begin

        state_fsm <= ST_INIT;
        proc_fsm  <= P_IDLE;

        row_enc <= 0;
        row_dec <= 0;

        block_idx <= 0;
        pixel_idx <= 0;

        is_encrypted <= 0;

        init_counter <= 0;

        aes_we <= 0;
        aes_rd <= 0;

        aes_addr  <= 0;
        aes_wdata <= 0;

        aes_in <= 0;

        enc_start <= 1;
        dec_start <= 1;

    end
    else begin

        state_fsm <= next_state_fsm;
        proc_fsm  <= next_proc_fsm;

        // default pulse inactive
        enc_start <= 1'b1;
        dec_start <= 1'b1;

        // default disable
        aes_we <= 1'b0;
        aes_rd <= 1'b0;

        //=====================================================================
        // INIT
        //=====================================================================
        if(state_fsm == ST_INIT) begin

            if(v_blank) begin

                aes_we <= 1'b1;

                aes_addr <= {4'b0000, init_counter};

                aes_wdata <= rom_data_out;

                if(init_counter != 14'd16383)
                    init_counter <= init_counter + 1'b1;
            end
        end

        //=====================================================================
        // NORMAL AES PROCESS
        //=====================================================================
        else begin

            case(proc_fsm)

                //=============================================================
                P_IDLE:
                begin
                    pixel_idx <= 0;
                end

                //=============================================================
                P_READ_REQ:
                begin
                    aes_rd <= 1'b1;

                    aes_addr <=
                    (
                        (state_fsm == ST_ENCRYPT) ?
                        18'h00000 :
                        18'h10000
                    )
                    +
                    (
                        (state_fsm == ST_ENCRYPT) ?
                        row_enc :
                        row_dec
                    ) * 128
                    +
                    block_idx * 8
                    +
                    pixel_idx;
                end

                //=============================================================
                P_READ_WAIT:
                begin

                    aes_in <=
                    {
                        aes_in[111:0],
                        sram_data_pipe
                    };

                    if(pixel_idx == 3'd7) begin

                        pixel_idx <= 0;

                        if(state_fsm == ST_ENCRYPT)
                            enc_start <= 1'b0;
                        else
                            dec_start <= 1'b0;

                    end
                    else begin
                        pixel_idx <= pixel_idx + 1'b1;
                    end
                end

                //=============================================================
                P_AES_WAIT:
                begin
                end

                //=============================================================
                P_WRITE:
                begin

                    aes_we <= 1'b1;

                    aes_addr <=
                    (
                        (state_fsm == ST_ENCRYPT) ?
                        18'h10000 :
                        18'h20000
                    )
                    +
                    (
                        (state_fsm == ST_ENCRYPT) ?
                        row_enc :
                        row_dec
                    ) * 128
                    +
                    block_idx * 8
                    +
                    pixel_idx;

                    aes_wdata <=
                    (
                        (state_fsm == ST_ENCRYPT)
                    ) ?

                    enc_out[127 - pixel_idx*16 -: 16]

                    :

                    dec_out[127 - pixel_idx*16 -: 16];

                    if(pixel_idx == 3'd7)
                        pixel_idx <= 0;
                    else
                        pixel_idx <= pixel_idx + 1'b1;
                end

                //=============================================================
                P_NEXT:
                begin

                    pixel_idx <= 0;

                    if(block_idx == 4'd15) begin

                        block_idx <= 0;

                        if(state_fsm == ST_ENCRYPT) begin

                            if(row_enc != 7'd127)
                                row_enc <= row_enc + 1'b1;
                            else
                                is_encrypted <= 1'b1;

                        end
                        else begin

                            if(row_dec != 7'd127)
                                row_dec <= row_dec + 1'b1;

                        end
                    end
                    else begin
                        block_idx <= block_idx + 1'b1;
                    end
                end

            endcase
        end
    end
end

endmodule