`default_nettype none

module protocol_core (
    input wire clk, input wire rst_n,
    input wire request, input wire [7:0] command, input wire [7:0] length,
    input wire [23:0] payload, output wire [63:0] response,
    output reg running, output wire fault,
    output wire [7:0] pin_out, output wire [7:0] pin_oe
);
    localparam STATUS = 8'h00, STOP = 8'h01, BEGIN_LOAD = 8'h02,
               WRITE_WORD = 8'h03, COMMIT_LOAD = 8'h04, CONFIG_OD = 8'h05,
               START = 8'h06, CLEAR = 8'h09;
    localparam OK = 8'd0, BAD_COMMAND = 8'd1, BAD_LENGTH = 8'd2,
               BAD_STATE = 8'd3, BAD_COUNT = 8'd4;
    reg [23:0] memory [0:63];
    reg valid, loading;
    // The extra bit represents the completed 64-word load or past-end fetch.
    reg [6:0] word_count, write_index, pc;
    reg [1:0] fault_code;
    assign fault = |fault_code;
    reg [15:0] delay_left;
    reg [7:0] out_latch, oe_latch, od_mask;
    assign pin_out = out_latch & ~od_mask;
    assign pin_oe = oe_latch & ~(out_latch & od_mask);

    reg [7:0] status;
    always @* begin
        status = OK;
        case (command)
            STATUS, STOP: if (length != 0) status = BAD_LENGTH;
            START, CLEAR, COMMIT_LOAD: begin
                if (length != 0) status = BAD_LENGTH;
                else if (running) status = BAD_STATE;
                else if (command == START && (!valid || fault)) status = BAD_STATE;
                else if (command == COMMIT_LOAD && (!loading || write_index != word_count))
                    status = BAD_STATE;
            end
            BEGIN_LOAD, CONFIG_OD: begin
                if (length != 1) status = BAD_LENGTH;
                else if (running) status = BAD_STATE;
                else if (command == BEGIN_LOAD && (payload[7:0] == 0 || payload[7:0] > 64))
                    status = BAD_COUNT;
            end
            WRITE_WORD: begin
                if (length != 3) status = BAD_LENGTH;
                else if (running || !loading || write_index >= word_count) status = BAD_STATE;
            end
            default: status = BAD_COMMAND;
        endcase
    end
    // STATUS snapshots state on the last request bit, before that edge executes.
    wire [7:0] flags = {6'b0, fault, running};
    assign response = (command == STATUS && status == OK)
                    ? {OK, 8'd6, 8'd1, flags, 6'b0, fault_code, 1'b0, pc, 16'b0}
                    : {status, 56'b0};
    wire accept = request && status == OK;
    // Reset clears loading and word_count, which reject WRITE_WORD requests.
    // Memory contents are retained until overwritten by a new complete load.
    always @(posedge clk)
        if (accept && command == WRITE_WORD)
            memory[write_index[5:0]] <= payload;

    wire [23:0] word = memory[pc[5:0]];
    wire [3:0] opcode = word[23:20];
    wire [7:0] mask = word[15:8];
    wire [7:0] value = word[7:0];
    wire illegal = (word[19:16] != 0) || (opcode > 3) ||
                   (opcode == 0 && word[15:0] != 0) ||
                   (opcode == 3 && word[15:0] == 0);
    wire past_end = pc >= word_count;
    wire stopping = accept && command == STOP;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running <= 0;
            fault_code <= 0;
            loading <= 0;
            valid <= 0;
            pc <= 0;
            word_count <= 0;
            write_index <= 0;
            delay_left <= 0;
            out_latch <= 0;
            oe_latch <= 0;
            od_mask <= 0;
        end else if (stopping || (running && (past_end || illegal || opcode == 0))) begin
            running <= 0;
            out_latch <= 0;
            oe_latch <= 0;
            delay_left <= 0;
            if (!stopping && past_end) fault_code <= 2;       // PC_RANGE
            else if (!stopping && illegal) fault_code <= 1;  // ILLEGAL_INSTRUCTION
        end else if (running) begin
            case (opcode)
                1: begin
                    out_latch <= (out_latch & ~mask) | (value & mask);
                    pc <= pc + 1'b1;
                end
                2: begin
                    oe_latch <= (oe_latch & ~mask) | (value & mask);
                    pc <= pc + 1'b1;
                end
                3: begin
                    if (delay_left == 0) delay_left <= word[15:0] - 1'b1;
                    else delay_left <= delay_left - 1'b1;
                    if (delay_left == 1 || (delay_left == 0 && word[15:0] == 1))
                        pc <= pc + 1'b1;
                end
                default: ;
            endcase
        end else if (accept) begin
            case (command)
                BEGIN_LOAD: begin
                    valid <= 0;
                    loading <= 1;
                    word_count <= payload[6:0];
                    write_index <= 0;
                end
                WRITE_WORD: write_index <= write_index + 1'b1;
                COMMIT_LOAD: begin
                    valid <= 1;
                    loading <= 0;
                end
                CONFIG_OD: od_mask <= payload[7:0];
                START: begin
                    pc <= 0;
                    running <= 1;
                end
                CLEAR: begin
                    pc <= 0;
                    fault_code <= 0;
                    write_index <= 0;
                    loading <= 0;
                end
                default: ;
            endcase
        end
    end
endmodule
