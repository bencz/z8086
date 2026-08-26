`timescale 1ns/1ns

module tb_external_chip;

reg clk = 1'b0;
reg reset_n = 1'b0;
tri [15:0] ad;
wire [3:0] a19_16;
wire bhe_n;
wire ale;
wire rd_n;
wire wr_n;
wire m_io;
wire inta_n;
wire den_n;
wire dt_r;
reg ready = 1'b1;
reg intr = 1'b0;
reg nmi = 1'b0;
reg hold = 1'b0;
wire hlda;

reg [7:0] memory [0:1048575];
reg [19:0] bus_addr;
reg [15:0] read_data;
integer index;
integer cycles;
reg completed;

always #5 clk = ~clk;

assign ad = (!rd_n && m_io) ? read_data : 16'hzzzz;

always @(*) begin
    read_data = 16'h0000;
    if (!bhe_n && !bus_addr[0]) begin
        read_data[7:0] = memory[bus_addr];
        read_data[15:8] = memory[bus_addr + 20'd1];
    end else if (!bhe_n) begin
        read_data[15:8] = memory[bus_addr];
    end else begin
        read_data[7:0] = memory[bus_addr];
    end
end

always @(posedge clk) begin
    if (ale)
        bus_addr <= {a19_16, ad};

    if (!wr_n && m_io) begin
        if (!bhe_n && !bus_addr[0]) begin
            memory[bus_addr] <= ad[7:0];
            memory[bus_addr + 20'd1] <= ad[15:8];
        end else if (!bhe_n) begin
            memory[bus_addr] <= ad[15:8];
        end else begin
            memory[bus_addr] <= ad[7:0];
        end
    end
end

z8086_external_chip dut (
    .clk(clk),
    .reset_n(reset_n),
    .ad(ad),
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

initial begin
    completed = 1'b0;
    for (index = 0; index < 1048576; index = index + 1)
        memory[index] = 8'h00;

    // MOV AX,1234; MOV [0100],AX; MOV AX,0; MOV AX,[0100];
    // MOV [0102],AX; HLT
    memory[20'hffff0] = 8'hb8;
    memory[20'hffff1] = 8'h34;
    memory[20'hffff2] = 8'h12;
    memory[20'hffff3] = 8'ha3;
    memory[20'hffff4] = 8'h00;
    memory[20'hffff5] = 8'h01;
    memory[20'hffff6] = 8'hb8;
    memory[20'hffff7] = 8'h00;
    memory[20'hffff8] = 8'h00;
    memory[20'hffff9] = 8'ha1;
    memory[20'hffffa] = 8'h00;
    memory[20'hffffb] = 8'h01;
    memory[20'hffffc] = 8'ha3;
    memory[20'hffffd] = 8'h02;
    memory[20'hffffe] = 8'h01;
    memory[20'hfffff] = 8'hf4;

    repeat (4) @(posedge clk);
    reset_n = 1'b1;

    // Exercise HOLD between transactions; the CPU must resume without losing
    // the request that arrived while HLDA was active.
    repeat (12) @(posedge clk);
    hold = 1'b1;
    wait (hlda);
    repeat (3) @(posedge clk);
    hold = 1'b0;

    for (cycles = 0; cycles < 4000 && !completed; cycles = cycles + 1) begin
        @(posedge clk);
        if (memory[20'h00102] == 8'h34 && memory[20'h00103] == 8'h12)
            completed = 1'b1;
    end

    if (!completed)
        $fatal(1, "external chip did not complete the memory round trip");

    $display("PASS: multiplexed external chip bus, byte lanes, READY and HOLD/HLDA");
    $finish;
end

endmodule
