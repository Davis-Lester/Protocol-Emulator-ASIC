`default_nettype none

// Mode 0, MSB first. All logic uses clk. The master leaves at least eight
// system clocks between CS/SCK transitions (see docs/ARCHITECTURE.md).
module protocol_spi (
    input wire clk, input wire rst_n, input wire [2:0] host_pins,
    output reg miso, output wire request, output reg [7:0] command,
    output wire [7:0] length, output wire [23:0] payload,
    input wire [63:0] response
);
    (* async_reg = "true" *) reg [2:0] sync1, sync2;
    reg last_sck;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= 0;
            sync2 <= 0;
            last_sck <= 0;
        end else begin
            sync1 <= host_pins;
            sync2 <= sync1;
            last_sck <= sync2[0];
        end
    end

    wire cs_n = sync2[2];
    wire rising = sync2[0] && !last_sck;
    wire falling = !sync2[0] && last_sck;
    localparam CMD = 2'd0, LEN = 2'd1, DATA = 2'd2, REPLY = 2'd3;
    reg [1:0] phase;
    reg [2:0] bit_index;
    reg [6:0] rx_bits;
    reg [15:0] previous_bytes;
    reg [7:0] declared, remaining;
    reg [63:0] tx_bits;
    wire [7:0] rx_byte = {rx_bits, sync2[1]};
    wire byte_done = !cs_n && rising && bit_index == 7;
    assign length = phase == LEN ? rx_byte : declared;
    assign payload = {previous_bytes, rx_byte};
    assign request = byte_done && ((phase == LEN && rx_byte == 0) ||
                                   (phase == DATA && remaining == 1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Ignore a request already in progress at reset release. Observe
            // synchronized CS high before accepting the first command.
            phase <= REPLY;
            bit_index <= 0;
            command <= 0;
            declared <= 0;
            remaining <= 0;
            rx_bits <= 0;
            previous_bytes <= 0;
            tx_bits <= 0;
            miso <= 0;
        end else if (cs_n) begin
            phase <= CMD;
            bit_index <= 0;
            miso <= 0;
            tx_bits <= 0;
        end else if (phase == REPLY) begin
            if (falling) begin
                miso <= tx_bits[63];
                tx_bits <= {tx_bits[62:0], 1'b0};
            end
        end else if (rising) begin
            rx_bits <= {rx_bits[5:0], sync2[1]};
            bit_index <= bit_index + 1'b1;
            if (byte_done) begin
                case (phase)
                    CMD: begin
                        command <= rx_byte;
                        phase <= LEN;
                    end
                    LEN: begin
                        declared <= rx_byte;
                        remaining <= rx_byte;
                        previous_bytes <= 0;
                        phase <= DATA;
                    end
                    DATA: begin
                        previous_bytes <= {previous_bytes[7:0], rx_byte};
                        remaining <= remaining - 1'b1;
                    end
                    default: phase <= REPLY;
                endcase
                if (request) begin
                    phase <= REPLY;
                    tx_bits <= response;
                end
            end
        end
    end
endmodule
