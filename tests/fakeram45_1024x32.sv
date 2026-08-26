module fakeram45_1024x32 (
    output logic [31:0] rd_out,
    input  logic  [9:0] addr_in,
    input  logic        we_in,
    input  logic [31:0] wd_in,
    input  logic [31:0] w_mask_in,
    input  logic        clk,
    input  logic        ce_in
);

logic [31:0] memory [0:1023];

always_ff @(posedge clk) begin
    if (ce_in) begin
        if (we_in) begin
            memory[addr_in] <= (memory[addr_in] & ~w_mask_in) |
                               (wd_in & w_mask_in);
        end else begin
            rd_out <= memory[addr_in];
        end
    end
end

endmodule
