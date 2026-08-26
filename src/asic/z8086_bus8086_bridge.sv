// Multiplexed external-bus adapter for the z8086 core.
//
// The CPU keeps its short internal request/ready interface.  This block alone
// implements the externally visible T1/T2/Twait/T4 sequencing, byte-lane
// steering, bus transceiver controls, and HOLD/HLDA arbitration.
`timescale 1ns/1ns

module z8086_bus8086_bridge (
    input  wire        clk,
    input  wire        reset_n,

    input  wire [19:0] core_addr,
    input  wire [15:0] core_dout,
    output reg  [15:0] core_din,
    input  wire        core_rd,
    input  wire        core_wr,
    input  wire        core_io,
    input  wire        core_word,
    input  wire        core_inta,
    output reg         core_ready,

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
    input  wire        hold,
    output reg         hlda
);

typedef enum logic [2:0] {
    BUS_IDLE,
    BUS_T1,
    BUS_T2,
    BUS_WAIT,
    BUS_T4,
    BUS_HOLD
} bus_phase_t;

bus_phase_t phase;
reg [19:0] request_addr;
reg [15:0] request_dout;
reg        request_rd;
reg        request_wr;
reg        request_io;
reg        request_word;
reg        request_inta;
reg        request_pending;

wire core_request = core_rd | core_wr | core_inta;
wire data_phase = (phase == BUS_T2) | (phase == BUS_WAIT);
wire odd_byte = request_addr[0] & ~request_word;

assign a19_16 = request_addr[19:16];
assign bhe_n = ~(request_word | odd_byte);
assign ale = phase == BUS_T1;
assign rd_n = ~(data_phase & request_rd & ~request_inta);
assign wr_n = ~(data_phase & request_wr);
assign inta_n = ~(data_phase & request_inta);
assign m_io = ~request_io & ~request_inta;
assign den_n = ~data_phase;
assign dt_r = request_wr;
assign ad_oe = (phase == BUS_T1) | (data_phase & request_wr);
assign ad_out = (phase == BUS_T1) ? request_addr[15:0] :
                odd_byte ? {request_dout[7:0], 8'h00} : request_dout;

task automatic latch_core_request;
begin
    request_addr <= core_addr;
    request_dout <= core_dout;
    request_rd <= core_rd;
    request_wr <= core_wr;
    request_io <= core_io;
    request_word <= core_word;
    request_inta <= core_inta;
end
endtask

task automatic complete_read;
begin
    if (request_rd | request_inta) begin
        if (request_word)
            core_din <= ad_in;
        else if (odd_byte)
            core_din <= {8'h00, ad_in[15:8]};
        else
            core_din <= {8'h00, ad_in[7:0]};
    end
    core_ready <= 1'b1;
end
endtask

always @(posedge clk) begin
    if (!reset_n) begin
        phase <= BUS_IDLE;
        request_addr <= 20'h00000;
        request_dout <= 16'h0000;
        request_rd <= 1'b0;
        request_wr <= 1'b0;
        request_io <= 1'b0;
        request_word <= 1'b0;
        request_inta <= 1'b0;
        request_pending <= 1'b0;
        core_din <= 16'h0000;
        core_ready <= 1'b0;
        hlda <= 1'b0;
    end else begin
        core_ready <= 1'b0;

        case (phase)
            BUS_IDLE: begin
                hlda <= 1'b0;
                if (core_request) begin
                    latch_core_request();
                    if (hold) begin
                        request_pending <= 1'b1;
                        hlda <= 1'b1;
                        phase <= BUS_HOLD;
                    end else begin
                        phase <= BUS_T1;
                    end
                end else if (hold) begin
                    hlda <= 1'b1;
                    phase <= BUS_HOLD;
                end
            end

            BUS_T1: phase <= BUS_T2;

            BUS_T2: begin
                if (ready) begin
                    complete_read();
                    phase <= BUS_T4;
                end else begin
                    phase <= BUS_WAIT;
                end
            end

            BUS_WAIT: begin
                if (ready) begin
                    complete_read();
                    phase <= BUS_T4;
                end
            end

            BUS_T4: begin
                if (hold) begin
                    hlda <= 1'b1;
                    phase <= BUS_HOLD;
                end else begin
                    phase <= BUS_IDLE;
                end
            end

            BUS_HOLD: begin
                hlda <= 1'b1;
                if (core_request & ~request_pending) begin
                    latch_core_request();
                    request_pending <= 1'b1;
                end
                if (!hold) begin
                    hlda <= 1'b0;
                    if (request_pending | core_request) begin
                        if (core_request & ~request_pending)
                            latch_core_request();
                        request_pending <= 1'b0;
                        phase <= BUS_T1;
                    end else begin
                        phase <= BUS_IDLE;
                    end
                end
            end

            default: phase <= BUS_IDLE;
        endcase
    end
end

endmodule
