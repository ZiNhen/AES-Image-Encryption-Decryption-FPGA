module top(input wire [2:0]KEY, input wire CLOCK_50);
	MasterController(.CLOCK_50(CLOCK_50), .reset_n(KEY[0]), .btn_enc(KEY[1]), .btn_dec(KEY[2]));
endmodule