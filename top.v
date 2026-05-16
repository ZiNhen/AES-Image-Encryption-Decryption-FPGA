module top(
    input  wire        CLOCK_50,    // 50MHz từ kit DE2
    input  wire        [2:0]KEY,     // Nút nhấn Reset (KEY0) - Bất đồng bộ
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
	MasterController(.CLOCK_50(CLOCK_50), 
					.reset_n(KEY[0]),
					.btn_enc(KEY[1]), 
					.btn_dec(KEY[2]), 
					.SRAM_ADDR(SRAM_ADDR), 
					.SRAM_DQ(SRAM_DQ), 
					.SRAM_WE_N(SRAM_WE_N), 
					.SRAM_OE_N(SRAM_OE_N), 
					.SRAM_UB_N(SRAM_UB_N), 
					.SRAM_LB_N(SRAM_LB_N), 
					.SRAM_CE_N(SRAM_CE_N),
    				.VGA_HS(VGA_HS), 
					.VGA_VS(VGA_VS),
					.VGA_R(VGA_R), 
					.VGA_G(VGA_G), 
					.VGA_B(VGA_B),
					.VGA_CLK(VGA_CLK), 
					.VGA_BLANK_N(VGA_BLANK_N), 
					.VGA_SYNC_N(VGA_SYNC_N));
endmodule