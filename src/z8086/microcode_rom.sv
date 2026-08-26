// z8086 immutable 8086 microcode store
//
// Logical contract for the eventual foundry mask-ROM macro:
//   * 512 words x 21 useful bits
//   * one synchronous read port
//   * output holds while enable is low
//   * one-cycle address-to-data latency
//
// The source image contains 24-bit hexadecimal words because that is the
// convenient textual representation; its upper three bits are required to be
// zero and are deliberately discarded here.
(* keep_hierarchy = "yes" *)
module microcode_rom (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        enable,
    input  wire [8:0]  addr,
    output reg  [20:0] data
);

reg [23:0] words [0:511];

initial begin
    $readmemh("ucode.hex", words);
end

always @(posedge clk) begin
    if (!reset_n)
        data <= 21'h000000;
    else if (enable)
        data <= words[addr][20:0];
end

endmodule
