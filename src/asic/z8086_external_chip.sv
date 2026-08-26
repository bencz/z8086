// Package-facing external-memory z8086 chip top.
`timescale 1ns/1ns

module z8086_external_chip (
    input  wire        clk,
    input  wire        reset_n,
    inout  wire [15:0] ad,
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

wire [15:0] ad_in = ad;
wire [15:0] ad_out;
wire        ad_oe;

assign ad = ad_oe ? ad_out : 16'hzzzz;

z8086_external_chip_core chip_core (
    .clk(clk),
    .reset_n(reset_n),
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
    .intr(intr),
    .nmi(nmi),
    .hold(hold),
    .hlda(hlda)
);

endmodule
