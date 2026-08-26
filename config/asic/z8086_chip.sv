module z8086_chip (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        intr,
    input  logic        nmi,
    output logic        inta,

    output logic [19:0] io_addr,
    output logic [15:0] io_dout,
    input  logic [15:0] io_din,
    output logic        io_rd,
    output logic        io_wr,
    output logic        io_word,
    input  logic        io_ready,

    input  logic        loader_enable,
    input  logic        loader_req,
    input  logic        loader_write,
    input  logic [19:0] loader_addr,
    input  logic [31:0] loader_wdata,
    input  logic  [3:0] loader_wstrb,
    output logic [31:0] loader_rdata,
    output logic        loader_ready
);

logic [19:0] cpu_addr;
logic [15:0] cpu_din;
logic [15:0] cpu_dout;
logic        cpu_wr;
logic        cpu_rd;
logic        cpu_io;
logic        cpu_word;
logic        cpu_ready;
logic [15:0] ram_rdata;
logic        ram_ready;
wire         cpu_reset_n = reset_n && !loader_enable;

wire ram_request = (cpu_rd || cpu_wr) && !cpu_io;

assign cpu_din = cpu_io ? io_din : ram_rdata;
assign cpu_ready = cpu_io ? io_ready : ram_ready;

assign io_addr = cpu_addr;
assign io_dout = cpu_dout;
assign io_rd = cpu_rd && cpu_io;
assign io_wr = cpu_wr && cpu_io;
assign io_word = cpu_word;

z8086 cpu (
    .clk(clk),
    .reset_n(cpu_reset_n),
    .addr(cpu_addr),
    .din(cpu_din),
    .dout(cpu_dout),
    .wr(cpu_wr),
    .rd(cpu_rd),
    .io(cpu_io),
    .word(cpu_word),
    .ready(cpu_ready),
    .intr(intr),
    .nmi(nmi),
    .inta(inta)
);

z8086_onchip_ram ram (
    .clk(clk),
    .reset_n(reset_n),
    .cpu_req(ram_request),
    .cpu_write(cpu_wr),
    .cpu_word(cpu_word),
    .cpu_addr(cpu_addr),
    .cpu_wdata(cpu_dout),
    .cpu_rdata(ram_rdata),
    .cpu_ready(ram_ready),
    .loader_req(loader_req),
    .loader_enable(loader_enable),
    .loader_write(loader_write),
    .loader_addr(loader_addr),
    .loader_wdata(loader_wdata),
    .loader_wstrb(loader_wstrb),
    .loader_rdata(loader_rdata),
    .loader_ready(loader_ready)
);

endmodule
