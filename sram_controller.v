module sram_controller (
    input  wire        clk,          // Xung nhịp hệ thống (ví dụ 50MHz)
    input  wire        reset,        // Tín hiệu reset
    
    // Giao tiếp với User Logic (AES Core hoặc VGA Controller)
    input  wire [17:0] i_addr,       // Địa chỉ muốn truy cập
    input  wire [15:0] i_data_write, // Dữ liệu muốn ghi (ví dụ: pixel ảnh mã hóa)
    input  wire        i_we,         // Xung cho phép ghi (Write Enable - High active)
    input  wire        i_rd,         // Xung cho phép đọc (Read Enable - High active)
    output reg  [15:0] o_data_read,  // Dữ liệu đọc về
    
    // Giao tiếp vật lý với chân SRAM trên kit DE2
    output wire [17:0] SRAM_ADDR,
    inout  wire [15:0] SRAM_DQ,
    output wire        SRAM_WE_N,
    output wire        SRAM_OE_N,
    output wire        SRAM_UB_N,
    output wire        SRAM_LB_N,
    output wire        SRAM_CE_N
);

    // Bật chip toàn thời gian và cho phép truy cập cả 16-bit
    assign SRAM_CE_N = 1'b0;
    assign SRAM_UB_N = 1'b0;
    assign SRAM_LB_N = 1'b0;

    // Chuyển đổi tín hiệu điều khiển (User logic dùng mức 1, SRAM dùng mức 0)
    assign SRAM_WE_N = ~i_we;
    assign SRAM_OE_N = ~i_rd;
    assign SRAM_ADDR = i_addr;

    // XỬ LÝ INOUT BUS DỮ LIỆU (Cực kỳ quan trọng)
    // Nếu đang ghi (i_we = 1), đẩy dữ liệu từ i_data_write ra SRAM_DQ
    // Nếu không ghi, để SRAM_DQ ở trạng thái tổng trở cao (High-Z) để SRAM tự bơm dữ liệu vào
    assign SRAM_DQ = (i_we) ? i_data_write : 16'hzzzz;

    // Bắt dữ liệu đọc về khi có xung clock
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            o_data_read <= 16'd0;
        end else if (i_rd) begin
            o_data_read <= SRAM_DQ; // Đọc dữ liệu từ SRAM đưa vào logic
        end
    end

endmodule