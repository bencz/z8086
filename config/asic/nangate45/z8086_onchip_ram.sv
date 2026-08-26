`ifndef Z8086_EXTERNAL_FAKERAM_MODEL
(* blackbox *) module fakeram45_1024x32 (
    output [31:0] rd_out,
    input [9:0] addr_in,
    input we_in,
    input [31:0] wd_in,
    input [31:0] w_mask_in,
    input clk,
    input ce_in
);
endmodule
`endif

// One mebibyte of byte-addressable SRAM built from 256 1024x32 hard macros.
// CPU reads use a registered 16x16 mux tree, keeping the 256-bank selection
// out of a single combinational timing path. The loader port is intended for
// manufacturing test and volatile program loading while the CPU is in reset.
module z8086_onchip_ram (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        cpu_req,
    input  logic        cpu_write,
    input  logic        cpu_word,
    input  logic [19:0] cpu_addr,
    input  logic [15:0] cpu_wdata,
    output logic [15:0] cpu_rdata,
    output logic        cpu_ready,

    input  logic        loader_req,
    input  logic        loader_enable,
    input  logic        loader_write,
    input  logic [19:0] loader_addr,
    input  logic [31:0] loader_wdata,
    input  logic  [3:0] loader_wstrb,
    output logic [31:0] loader_rdata,
    output logic        loader_ready
);

typedef enum logic [2:0] {
    RAM_IDLE,
    RAM_ACCESS,
    RAM_CAPTURE_TILES,
    RAM_CAPTURE_ROWS,
    RAM_RESPONSE
} ram_state_t;

ram_state_t state;
logic [31:0] bank_read_data [0:255];
logic [31:0] tile_read_data [0:63];
logic [31:0] row_read_data [0:15];
logic  [3:0] selected_row;
logic  [7:0] selected_bank;
logic  [1:0] selected_byte;
logic        selected_loader;
logic        selected_write;
logic        selected_word;
logic [63:0] tile_enable;
logic  [9:0] tile_addr [0:63];
// The read selects are intentionally replicated at the physical mux leaves.
// Per-tile/per-row enables below make the copies structurally distinct, so
// synthesis cannot collapse the read hotpath into a die-wide select net.
// Address and write data remain shared: replicating those buses creates more
// clock/data distribution load without shortening the read mux path.
logic  [1:0] tile_column [0:63];
logic  [1:0] row_column [0:15];
logic [31:0] tile_write_data [0:63];
logic [31:0] tile_write_mask [0:63];
logic        tile_write [0:63];

wire loader_access = loader_req && loader_enable;
wire access_req = loader_access || cpu_req;
wire access_write = loader_access ? loader_write : cpu_write;
wire [19:0] access_addr = loader_access ? loader_addr : cpu_addr;
wire [7:0] access_bank = access_addr[19:12];
wire access_accept = (state == RAM_IDLE) && access_req;

logic [31:0] macro_write_data;
logic [31:0] macro_write_mask;

always_comb begin
    macro_write_data = loader_wdata;
    macro_write_mask = {
        {8{loader_wstrb[3]}},
        {8{loader_wstrb[2]}},
        {8{loader_wstrb[1]}},
        {8{loader_wstrb[0]}}
    };

    if (!loader_access) begin
        macro_write_data = 32'b0;
        macro_write_mask = 32'b0;
        if (cpu_word) begin
            if (cpu_addr[1]) begin
                macro_write_data[31:16] = cpu_wdata;
                macro_write_mask[31:16] = 16'hffff;
            end else begin
                macro_write_data[15:0] = cpu_wdata;
                macro_write_mask[15:0] = 16'hffff;
            end
        end else begin
            case (cpu_addr[1:0])
                2'd0: begin
                    macro_write_data[7:0] = cpu_wdata[7:0];
                    macro_write_mask[7:0] = 8'hff;
                end
                2'd1: begin
                    macro_write_data[15:8] = cpu_wdata[7:0];
                    macro_write_mask[15:8] = 8'hff;
                end
                2'd2: begin
                    macro_write_data[23:16] = cpu_wdata[7:0];
                    macro_write_mask[23:16] = 8'hff;
                end
                2'd3: begin
                    macro_write_data[31:24] = cpu_wdata[7:0];
                    macro_write_mask[31:24] = 8'hff;
                end
            endcase
        end
    end
end

// The read mux pipeline free-runs.  Its values are observed only after the
// RAM_CAPTURE_TILES/RAM_CAPTURE_ROWS sequence, so holding or resetting these
// internal registers has no architectural effect.  Unconditional capture
// maps to plain DFFs instead of thousands of DFF input hold muxes and removes
// the state/reset distribution tree from the RAM read timing path.
always_ff @(posedge clk) begin
    for (integer tile_index = 0; tile_index < 64; tile_index++) begin
        if (selected_bank[7:2] == tile_index[5:0]) begin
            tile_column[tile_index] <= selected_bank[1:0];
        end
        tile_read_data[tile_index] <=
            bank_read_data[tile_index * 4 +
                           integer'(tile_column[tile_index])];
    end
    for (integer row_index = 0; row_index < 16; row_index++) begin
        if (selected_bank[7:4] == row_index[3:0]) begin
            row_column[row_index] <= selected_bank[3:2];
        end
        row_read_data[row_index] <=
            tile_read_data[row_index * 4 +
                           integer'(row_column[row_index])];
    end
end

for (genvar bank_index = 0; bank_index < 256; bank_index++) begin : memory_bank
    localparam integer ROW_INDEX = bank_index / 16;
    localparam integer COLUMN_INDEX = bank_index % 16;
    localparam integer TILE_INDEX = ROW_INDEX * 4 + COLUMN_INDEX / 4;
    localparam integer TILE_COLUMN = COLUMN_INDEX % 4;
    localparam logic [1:0] TILE_COLUMN_BITS = TILE_COLUMN[1:0];
    // The macro is selected from the central bank snapshot during RAM_ACCESS.
    // The tile-local copy is filled on that same edge for the following read
    // mux stage, retiming the local decode without adding an interface cycle.
    wire bank_enable = tile_enable[TILE_INDEX] &&
                       (selected_bank[1:0] == TILE_COLUMN_BITS);

    fakeram45_1024x32 mem (
        .rd_out(bank_read_data[bank_index]),
        .addr_in(tile_addr[TILE_INDEX]),
        .we_in(tile_write[TILE_INDEX]),
        .wd_in(tile_write_data[TILE_INDEX]),
        .w_mask_in(tile_write_mask[TILE_INDEX]),
        .clk(clk),
        .ce_in(bank_enable)
    );
end

always_ff @(posedge clk) begin
    if (!reset_n) begin
        state <= RAM_IDLE;
        selected_row <= 4'b0;
        selected_bank <= 8'b0;
        selected_byte <= 2'b0;
        selected_loader <= 1'b0;
        selected_write <= 1'b0;
        selected_word <= 1'b0;
        tile_enable <= 64'b0;
        cpu_rdata <= 16'b0;
        cpu_ready <= 1'b0;
        loader_rdata <= 32'b0;
        loader_ready <= 1'b0;
    end else begin
        cpu_ready <= 1'b0;
        loader_ready <= 1'b0;

        case (state)
            RAM_IDLE: begin
                if (access_accept) begin
                    selected_row <= access_bank[7:4];
                    selected_bank <= access_bank;
                    selected_byte <= access_addr[1:0];
                    selected_loader <= loader_access;
                    selected_write <= access_write;
                    selected_word <= cpu_word;
                    for (integer tile_index = 0; tile_index < 64; tile_index++) begin
                        tile_enable[tile_index] <=
                            (access_bank[7:2] == tile_index[5:0]);
                        tile_addr[tile_index] <= access_addr[11:2];
                        tile_write_data[tile_index] <= macro_write_data;
                        tile_write_mask[tile_index] <= macro_write_mask;
                        tile_write[tile_index] <= access_write;
                    end
                    state <= RAM_ACCESS;
                end
            end

            RAM_ACCESS: begin
                tile_enable <= 64'b0;
                state <= selected_write ? RAM_RESPONSE : RAM_CAPTURE_TILES;
            end

            RAM_CAPTURE_TILES: begin
                state <= RAM_CAPTURE_ROWS;
            end

            RAM_CAPTURE_ROWS: begin
                state <= RAM_RESPONSE;
            end

            RAM_RESPONSE: begin
                if (selected_loader) begin
                    if (!selected_write) begin
                        loader_rdata <= row_read_data[selected_row];
                    end
                    loader_ready <= 1'b1;
                end else begin
                    if (!selected_write) begin
                        if (selected_word) begin
                            cpu_rdata <= selected_byte[1]
                                ? row_read_data[selected_row][31:16]
                                : row_read_data[selected_row][15:0];
                        end else begin
                            case (selected_byte)
                                2'd0: cpu_rdata <= {8'b0, row_read_data[selected_row][7:0]};
                                2'd1: cpu_rdata <= {8'b0, row_read_data[selected_row][15:8]};
                                2'd2: cpu_rdata <= {8'b0, row_read_data[selected_row][23:16]};
                                2'd3: cpu_rdata <= {8'b0, row_read_data[selected_row][31:24]};
                            endcase
                        end
                    end
                    cpu_ready <= 1'b1;
                end
                state <= RAM_IDLE;
            end

            default: state <= RAM_IDLE;
        endcase
    end
end

endmodule
