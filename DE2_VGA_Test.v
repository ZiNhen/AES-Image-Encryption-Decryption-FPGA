module DE2_VGA_Test(
    input         CLOCK_50,    // Xung nhịp 50MHz của DE2
    input  [0:0]  KEY,         // Nút nhấn KEY[0] dùng làm Reset

    // --- Các chân giao tiếp VGA (nối ra port VGA của DE2) ---
    output [9:0]  VGA_R,
    output [9:0]  VGA_G,
    output [9:0]  VGA_B,
    output        VGA_CLK,
    output        VGA_BLANK,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_SYNC,

    // --- Các chân giao tiếp SRAM (nối ra chip SRAM của DE2) ---
    output [17:0] SRAM_ADDR,
    inout  [15:0] SRAM_DQ,
    output        SRAM_CE_N,
    output        SRAM_OE_N,
    output        SRAM_WE_N,
    output        SRAM_UB_N,
    output        SRAM_LB_N
);

    wire reset = ~KEY[0]; // Nhấn KEY[0] xuống mức 0 -> reset mức 1

    // 1. Tạo xung nhịp 25MHz cho VGA từ xung 50MHz
    // Để đơn giản cho bài test, ta dùng một bộ chia tần số bằng Flip-Flop
    reg clk_25mhz;
    always @(posedge CLOCK_50 or posedge reset) begin
        if (reset) clk_25mhz <= 1'b0;
        else       clk_25mhz <= ~clk_25mhz;
    end

    // 2. Khởi tạo VGA Controller
    wire [9:0] x_pos, y_pos;
    wire       video_on;
    
    vga_controller u_vga (
        .clk_25mhz(clk_25mhz),
        .reset(reset),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .x_pos(x_pos),
        .y_pos(y_pos),
        .video_on(video_on)
    );

    // 3. Tính toán địa chỉ SRAM
    // Chỉ cấp địa chỉ đọc khi tia quét nằm trong vùng ảnh 320x240
    wire is_image_area = (x_pos < 320) && (y_pos < 240);
    wire [17:0] sram_addr_req;
    
    // Công thức tính địa chỉ mảng 1 chiều từ tọa độ 2 chiều (X, Y)
    assign sram_addr_req = is_image_area ? ((y_pos * 320) + x_pos) : 18'd0;

    // 4. Khởi tạo SRAM Controller
    wire [15:0] sram_pixel_data;
    
    sram_controller u_sram (
        .clk(CLOCK_50),         // SRAM chạy ở 50MHz để đọc nhanh
        .reset(reset),
        .i_addr(sram_addr_req),
        .i_data_write(16'd0),   // Bài test này chỉ đọc, không ghi
        .i_we(1'b0),            // Tắt chức năng ghi
        .i_rd(1'b1),            // Luôn bật chức năng đọc
        .o_data_read(sram_pixel_data),
        
        // Tín hiệu vật lý
        .SRAM_ADDR(SRAM_ADDR),
        .SRAM_DQ(SRAM_DQ),
        .SRAM_WE_N(SRAM_WE_N),
        .SRAM_OE_N(SRAM_OE_N),
        .SRAM_UB_N(SRAM_UB_N),
        .SRAM_LB_N(SRAM_LB_N),
        .SRAM_CE_N(SRAM_CE_N)
    );

    // 5. Xử lý màu sắc xuất ra màn hình
    // Nếu nằm trong vùng ảnh và video_on = 1, xuất pixel từ SRAM. Ngược lại xuất màu đen.
    wire [15:0] display_color = (is_image_area && video_on) ? sram_pixel_data : 16'h0000;

    // Ánh xạ RGB565 sang chuẩn 10-bit của chip DAC ADV7123 trên kit DE2
    assign VGA_R = {display_color[15:11], display_color[15:11]};
    assign VGA_G = {display_color[10:5],  display_color[10:7]};
    assign VGA_B = {display_color[4:0],   display_color[4:0]};

    // Tín hiệu điều khiển chip DAC VGA
    assign VGA_CLK   = clk_25mhz;
    assign VGA_BLANK = video_on; // Rất quan trọng: Chip DAC cần tín hiệu này để đồng bộ
    assign VGA_SYNC  = 1'b0;

endmodule