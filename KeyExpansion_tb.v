`timescale 1ns/1ps

module KeyEpansion_tb();
reg [127:0] key;
reg [7:0] rcon;
wire [127:0] next_key;

KeyExpansion ke(.prev_key(key), .rcon(rcon), .next_key(next_key));

initial begin

key = 128'h2b7e151628aed2a6abf7158809cf4f3c;
rcon = 8'h01;
#10

if (next_key == 128'ha0fafe1788542cb123a339392a6c7605) begin
$display("\n=> KET QUA: PASSED! Mach hoat dong dung chuan NIST.");
end else begin
    $display("\n=> KET QUA: FAILED! Ket qua khong khop voi NIST vector.");
    $display("Gia tri mong doi : a0fafe1788542cb123a339392a6c7605");
    $display("Gia tri thuc te  : %h", next_key);
    end
$stop;
end

endmodule