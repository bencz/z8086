// Process-neutral core-facing boundary for the package pad cells.
`timescale 1ns/1ns

module z8086_external_chip_core (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [15:0] ad_in,
    output wire [15:0] ad_out,
    output wire        ad_oe,
    output wire  [3:0] a19_16,
    output wire        bhe_n,
    output wire        ale,
    output wire        rd_n,
    output wire        wr_n,
    output wire        m_io,
    output wire        inta_n,
    output wire        den_n,
    output wire        dt_r,
    input  wire        ready,
    input  wire        intr,
    input  wire        nmi,
    input  wire        hold,
    output wire        hlda
);

wire [19:0] core_addr;
wire [15:0] core_din;
wire [15:0] core_dout;
wire        core_wr;
wire        core_rd;
wire        core_io;
wire        core_word;
wire        core_ready;
wire        core_inta;

z8086 cpu (
    .clk(clk),
    .reset_n(reset_n),
    .addr(core_addr),
    .din(core_din),
    .dout(core_dout),
    .wr(core_wr),
    .rd(core_rd),
    .io(core_io),
    .word(core_word),
    .ready(core_ready),
    .intr(intr),
    .nmi(nmi),
    .inta(core_inta)
);

z8086_bus8086_bridge bus_bridge (
    .clk(clk),
    .reset_n(reset_n),
    .core_addr(core_addr),
    .core_dout(core_dout),
    .core_din(core_din),
    .core_rd(core_rd),
    .core_wr(core_wr),
    .core_io(core_io),
    .core_word(core_word),
    .core_inta(core_inta),
    .core_ready(core_ready),
    .ad_in(ad_in),
    .ad_out(ad_out),
    .ad_oe(ad_oe),
    .a19_16(a19_16),
    .bhe_n(bhe_n),
    .ale(ale),
    .rd_n(rd_n),
    .wr_n(wr_n),
    .m_io(m_io),
    .inta_n(inta_n),
    .den_n(den_n),
    .dt_r(dt_r),
    .ready(ready),
    .hold(hold),
    .hlda(hlda)
);

endmodule
