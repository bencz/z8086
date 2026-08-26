`timescale 1ns/1ns

// Headless simulation of the HDMI demo SoC.
// It replaces FPGA PLL/HDMI/UART primitives with byte-addressable RAM, VRAM
// and a scripted UART so the real soc_hdmi firmware can run in Verilator.
module tb_soc_headless;
  import "DPI-C" function int host_terminal_init();
  import "DPI-C" function int host_poll_key();
  import "DPI-C" function void host_terminal_restore();

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg reset_n = 1'b0;
  wire [19:0] addr;
  reg  [15:0] din = 16'h0000;
  wire [15:0] dout;
  wire rd, wr, io, word, inta;
  reg ready = 1'b0;

  z8086 cpu (
    .clk(clk), .reset_n(reset_n),
    .addr(addr), .din(din), .dout(dout),
    .wr(wr), .rd(rd), .io(io), .word(word), .ready(ready),
    .intr(1'b0), .nmi(1'b0), .inta(inta)
  );

  localparam integer RAM_BYTES = 128 * 1024;
  localparam integer VRAM_BYTES = 8 * 1024;
  reg [7:0] mem [0:RAM_BYTES-1];
  reg [7:0] vram [0:VRAM_BYTES-1];

  reg pending = 1'b0;
  reg req_rd, req_wr, req_io, req_word;
  reg [19:0] req_addr;
  reg [15:0] req_dout;

  string firmware;
  string command_text;
  string keys_text;
  string rx_script;
  integer rx_index = 0;
  integer rx_gap = 1000;
  longint next_rx_cycle = 0;
  longint sim_cycle = 0;
  integer max_cycles = 3_000_000;
  integer interactive = 0;
  integer redraw_interval = 100_000;
  integer snake_delay = 2000;
  integer poll_count = 0;
  integer redraw_count = 0;
  integer polled_key = -1;
  integer host_key = -1;
  reg host_key_valid = 1'b0;
  reg [6:0] leds = 7'h00;

  wire script_available = (rx_index < rx_script.len()) &&
                          (sim_cycle >= next_rx_cycle);
  wire rx_available = script_available || (interactive != 0 && host_key_valid);

  function automatic [15:0] memory_read(input [19:0] a, input logic is_word);
    integer base;
    begin
      if (a >= 20'hB8000 && a < 20'hBA000) begin
        base = a - 20'hB8000;
        memory_read = is_word ? {vram[base + 1], vram[base]} :
                               {8'h00, vram[base]};
      end else begin
        base = a[16:0];
        memory_read = is_word ? {mem[(base + 1) & 17'h1ffff], mem[base]} :
                               {8'h00, mem[base]};
      end
    end
  endfunction

  task automatic memory_write(
    input [19:0] a,
    input logic is_word,
    input [15:0] value
  );
    integer base;
    begin
      if (a >= 20'hB8000 && a < 20'hBA000) begin
        base = a - 20'hB8000;
        vram[base] = value[7:0];
        if (is_word) vram[base + 1] = value[15:8];
      end else begin
        base = a[16:0];
        mem[base] = value[7:0];
        if (is_word) mem[(base + 1) & 17'h1ffff] = value[15:8];
      end
    end
  endtask

  task automatic dump_screen;
    integer row, col;
    reg [7:0] ch;
    begin
      $display("\n---- VRAM 80x30 ----");
      for (row = 0; row < 30; row = row + 1) begin
        for (col = 0; col < 80; col = col + 1) begin
          ch = vram[(row * 80 + col) * 2];
          if (ch >= 8'h20 && ch <= 8'h7e) $write("%c", ch);
          else                            $write(" ");
        end
        $write("\n");
      end
      $display("---- END VRAM ----");
    end
  endtask

  task automatic draw_interactive_screen;
    integer row, col;
    reg [7:0] ch;
    begin
      $write("\033[H");
      for (row = 0; row < 30; row = row + 1) begin
        for (col = 0; col < 80; col = col + 1) begin
          ch = vram[(row * 80 + col) * 2];
          if (ch >= 8'h20 && ch <= 8'h7e) $write("%c", ch);
          else                            $write(" ");
        end
        $write("\n");
      end
      $write("\033[33mWASD: mover | Q: sair do jogo | ESC: encerrar simulador\033[0m\n");
    end
  endtask

  // One outstanding transaction, completed one clock after its request pulse.
  always @(posedge clk) begin
    sim_cycle <= sim_cycle + 1;
    ready <= 1'b0;

    if (interactive != 0) begin
      if (poll_count == 0) begin
        poll_count <= 10_000;
        if (!host_key_valid) begin
          polled_key = host_poll_key();
          if (polled_key == 8'h1b) begin
            host_terminal_restore();
            $write("\033[0m\n");
            $finish;
          end else if (polled_key >= 0) begin
            host_key <= polled_key;
            host_key_valid <= 1'b1;
          end
        end
      end else begin
        poll_count <= poll_count - 1;
      end

      if (redraw_count == 0) begin
        redraw_count <= redraw_interval;
        draw_interactive_screen();
      end else begin
        redraw_count <= redraw_count - 1;
      end
    end

    if (!reset_n) begin
      pending <= 1'b0;
      din <= 16'h0000;
    end else begin
      if (pending) begin
        pending <= 1'b0;
        ready <= 1'b1;
        if (req_io) begin
          if (req_rd) begin
            case (req_addr[7:0])
            8'h05: din <= {9'h000, leds};
            8'h06: din <= 16'h0000;
            8'h07: begin
              if (script_available) begin
                din <= {8'h00, rx_script.getc(rx_index)};
                rx_index <= rx_index + 1;
                next_rx_cycle <= sim_cycle + rx_gap;
              end else if (interactive != 0 && host_key_valid) begin
                din <= {8'h00, host_key[7:0]};
                host_key_valid <= 1'b0;
              end else begin
                din <= 16'h0000;
              end
            end
            8'h08: din <= {8'h00, 2'b00, 1'b1, 4'b0000, rx_available};
            default: din <= 16'h0000;
            endcase
          end
          if (req_wr) begin
            case (req_addr[7:0])
            8'h05: leds <= req_dout[6:0];
            8'h07: if (interactive == 0) $write("%c", req_dout[7:0]);
            default: ;
            endcase
          end
        end else begin
          if (req_rd) din <= memory_read(req_addr, req_word);
          if (req_wr) memory_write(req_addr, req_word, req_dout);
        end
      end

      if ((rd || wr || inta) && !pending) begin
        pending <= 1'b1;
        req_rd <= rd;
        req_wr <= wr;
        req_io <= io;
        req_word <= word;
        req_addr <= addr;
        req_dout <= dout;
      end
    end
  end

  initial begin
    integer i;
    for (i = 0; i < RAM_BYTES; i = i + 1) mem[i] = 8'h00;
    for (i = 0; i < VRAM_BYTES; i = i + 1) vram[i] = 8'h00;

    firmware = "../src/soc_hdmi/soc_hdmi.hex";
    command_text = "snake";
    keys_text = "x"; // starts the game after the board is drawn
    void'($value$plusargs("firmware=%s", firmware));
    void'($value$plusargs("command=%s", command_text));
    void'($value$plusargs("keys=%s", keys_text));
    void'($value$plusargs("rx_gap=%d", rx_gap));
    void'($value$plusargs("cycles=%d", max_cycles));
    void'($value$plusargs("interactive=%d", interactive));
    void'($value$plusargs("redraw=%d", redraw_interval));
    void'($value$plusargs("snake_delay=%d", snake_delay));
    rx_script = $sformatf("%s\n%s", command_text, keys_text);

    $readmemh(firmware, mem);
    if (interactive != 0) begin
      if (host_terminal_init() == 0)
        $fatal(1, "interactive mode requires a TTY on stdin");

      // The FPGA firmware deliberately burns five loops of 20,000 iterations
      // per Snake step. Reduce only those immediates in simulation so input
      // and redraw remain responsive; the checked-in firmware is unchanged.
      mem[17'h1100a] = snake_delay[7:0];
      mem[17'h1100b] = snake_delay[15:8];
      mem[17'h11020] = snake_delay[7:0];
      mem[17'h11021] = snake_delay[15:8];
      mem[17'h11036] = snake_delay[7:0];
      mem[17'h11037] = snake_delay[15:8];
      mem[17'h1104c] = snake_delay[7:0];
      mem[17'h1104d] = snake_delay[15:8];
      mem[17'h11062] = snake_delay[7:0];
      mem[17'h11063] = snake_delay[15:8];
      $write("\033[2J\033[H");
    end
    if ($test$plusargs("trace")) begin
      $dumpfile("soc_headless.fst");
      $dumpvars(0, tb_soc_headless);
    end

    repeat (5) @(posedge clk);
    reset_n = 1'b1;
    if (interactive != 0) begin
      forever @(posedge clk);
    end else begin
      repeat (max_cycles) @(posedge clk);
      dump_screen();
      $display("[SOC] cycles=%0d CS:IP=%04x:%04x LEDs=%02x RX=%0d/%0d",
               max_cycles, cpu.CS, cpu.IP, leds, rx_index, rx_script.len());
      $finish;
    end
  end
endmodule
