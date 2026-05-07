module vga_controller(
    input clk_25mhz,        // Xung pixel clock 25MHz
    input reset,
    output reg hsync,       // Xung đồng bộ ngang
    output reg vsync,       // Xung đồng bộ dọc
    output reg [9:0] x_pos, // Tọa độ X hiện tại (0-639)
    output reg [9:0] y_pos, // Tọa độ Y hiện tại (0-479)
    output video_on         // Báo hiệu đang ở trong vùng hiển thị (để xuất màu)
);

    reg [9:0] h_count;
    reg [9:0] v_count;

    // Bộ đếm quét màn hình
    always @(posedge clk_25mhz or posedge reset) begin
        if (reset) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == 799) begin
                h_count <= 0;
                if (v_count == 524)
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    // Tạo tín hiệu HSYNC và VSYNC (Tích cực mức thấp)
    always @(*) begin
        hsync = ~((h_count >= 640 + 16) && (h_count < 640 + 16 + 96));
        vsync = ~((v_count >= 480 + 10) && (v_count < 480 + 10 + 2));
    end

    // Báo hiệu vùng hiển thị hợp lệ
    assign video_on = (h_count < 640) && (v_count < 480);

    // Cập nhật tọa độ X, Y để xuất ra ngoài
    always @(*) begin
        x_pos = (video_on) ? h_count : 10'd0;
        y_pos = (video_on) ? v_count : 10'd0;
    end
endmodule