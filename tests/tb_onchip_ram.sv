module tb_onchip_ram;

logic clk;
logic reset_n = 1'b0;
logic cpu_req = 1'b0;
logic cpu_write = 1'b0;
logic cpu_word = 1'b0;
logic [19:0] cpu_addr = 20'b0;
logic [15:0] cpu_wdata = 16'b0;
logic [15:0] cpu_rdata;
logic cpu_ready;
logic loader_req = 1'b0;
logic loader_enable = 1'b1;
logic loader_write = 1'b0;
logic [19:0] loader_addr = 20'b0;
logic [31:0] loader_wdata = 32'b0;
logic [3:0] loader_wstrb = 4'b0;
logic [31:0] loader_rdata;
logic loader_ready;

initial clk = 1'b0;
always #1 clk = ~clk;

z8086_onchip_ram dut (.*);

task automatic loader_transaction(
    input logic write_access,
    input logic [19:0] address,
    input logic [31:0] write_data,
    input logic [3:0] write_strobes,
    output logic [31:0] read_data
);
begin
    @(negedge clk);
    loader_write = write_access;
    loader_addr = address;
    loader_wdata = write_data;
    loader_wstrb = write_strobes;
    loader_req = 1'b1;
    do @(negedge clk); while (!loader_ready);
    read_data = loader_rdata;
    loader_req = 1'b0;
end
endtask

task automatic cpu_transaction(
    input logic write_access,
    input logic word_access,
    input logic [19:0] address,
    input logic [15:0] write_data,
    output logic [15:0] read_data
);
begin
    @(negedge clk);
    cpu_write = write_access;
    cpu_word = word_access;
    cpu_addr = address;
    cpu_wdata = write_data;
    cpu_req = 1'b1;
    do @(negedge clk); while (!cpu_ready);
    read_data = cpu_rdata;
    cpu_req = 1'b0;
end
endtask

logic [31:0] observed_loader;
logic [15:0] observed_cpu;
logic [31:0] expected;

initial begin
    repeat (4) @(posedge clk);
    reset_n = 1'b1;

    // Exercise every physical SRAM bank through the loader port.  One
    // consolidated loop catches bank decode, macro address and mux-tree bugs.
    for (integer bank = 0; bank < 256; bank++) begin
        expected = 32'h5a00_0000 ^ (bank * 32'h0001_0201);
        loader_transaction(1'b1, {bank[7:0], 10'h155, 2'b00},
                           expected, 4'hf, observed_loader);
    end
    for (integer bank = 0; bank < 256; bank++) begin
        expected = 32'h5a00_0000 ^ (bank * 32'h0001_0201);
        loader_transaction(1'b0, {bank[7:0], 10'h155, 2'b00},
                           32'b0, 4'b0, observed_loader);
        if (observed_loader !== expected) begin
            $fatal(1, "loader bank %0d: expected %08x got %08x",
                   bank, expected, observed_loader);
        end
    end

    // Byte strobes and all four CPU byte lanes share one backing word.
    loader_transaction(1'b1, 20'h42a00, 32'h1122_3344, 4'hf,
                       observed_loader);
    loader_transaction(1'b1, 20'h42a00, 32'haa00_cc00, 4'b1010,
                       observed_loader);
    loader_transaction(1'b0, 20'h42a00, 32'b0, 4'b0, observed_loader);
    if (observed_loader !== 32'haa22_cc44)
        $fatal(1, "loader strobes: got %08x", observed_loader);

    for (integer lane = 0; lane < 4; lane++) begin
        cpu_transaction(1'b1, 1'b0,
                        20'h42a00 + {18'b0, lane[1:0]},
                        16'h0080 + {14'b0, lane[1:0]}, observed_cpu);
    end
    loader_transaction(1'b0, 20'h42a00, 32'b0, 4'b0, observed_loader);
    if (observed_loader !== 32'h8382_8180)
        $fatal(1, "CPU byte lanes: got %08x", observed_loader);

    // Both 16-bit halves, including the read-data half selector.
    cpu_transaction(1'b1, 1'b1, 20'h7f3a0, 16'hcafe, observed_cpu);
    cpu_transaction(1'b1, 1'b1, 20'h7f3a2, 16'hbabe, observed_cpu);
    cpu_transaction(1'b0, 1'b1, 20'h7f3a0, 16'b0, observed_cpu);
    if (observed_cpu !== 16'hcafe)
        $fatal(1, "CPU low word: got %04x", observed_cpu);
    cpu_transaction(1'b0, 1'b1, 20'h7f3a2, 16'b0, observed_cpu);
    if (observed_cpu !== 16'hbabe)
        $fatal(1, "CPU high word: got %04x", observed_cpu);

    $display("PASS: consolidated 1 MiB on-die RAM regression");
    $finish;
end

endmodule
