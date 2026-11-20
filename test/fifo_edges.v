`timescale 1ns/1ps
`default_nettype none

// Drive the core request on a specific execution edge to exercise arbitration.
module fifo_edges;
    reg clk = 0, rst_n = 0, request = 0;
    reg [7:0] command = 0, length = 0;
    reg [23:0] payload = 0;
    wire [63:0] response;
    wire running, fault, tx_ready;
    wire [7:0] pin_out, pin_oe;
    protocol_core dut(.clk(clk), .rst_n(rst_n), .request(request),
        .command(command), .length(length), .payload(payload), .response(response),
        .running(running), .fault(fault), .tx_ready(tx_ready),
        .pin_out(pin_out), .pin_oe(pin_oe));

    task tick;
        begin #25 clk = 1; #25 clk = 0; end
    endtask

    task send;
        input [7:0] op, size;
        input [23:0] data;
        input [7:0] expected;
        begin
            command = op; length = size; payload = data; request = 1;
            #1;
            if (response[63:56] !== expected)
                $fatal(1, "command %h returned %h, expected %h", op, response[63:56], expected);
            tick;
            request = 0;
        end
    endtask

    task check_state;
        input [7:0] expected_pc, count, code;
        begin
            command = 0; length = 0; #1;
            if ({response[23:16], response[15:8], response[31:24]} !== {expected_pc, count, code})
                $fatal(1, "unexpected STATUS response %h", response);
        end
    endtask

    initial begin
        tick; rst_n = 1;
        send(2,1,3,0); send(3,3,24'h800002,0); // GET_TX 2
        send(3,3,24'h900001,0); send(3,3,0,0); // TXBIT P1 LSB then HALT
        send(4,0,0,0); send(6,0,0,0);
        tick; check_state(0,0,0);            // First empty check.
        send(7,1,1,0); check_state(1,0,0);   // Last chance, empty FIFO bypass.
        tick;
        if (pin_out !== 2) $fatal(1, "empty FIFO bypass lost byte");
        tick; send(6,0,0,0);
        tick; tick; check_state(0,0,4);      // No write on the last allowed edge.
        send(7,1,1,0); check_state(0,1,4);   // Late write stays queued.
        send(9,0,0,0);
        send(7,1,1,0); send(7,1,2,0); send(7,1,3,0); send(7,1,4,0);
        send(6,0,0,0); send(7,1,0,5);        // Full at start of the pop edge.
        check_state(1,3,0); tick;
        if (pin_out !== 2) $fatal(1, "full FIFO collision replaced oldest byte");
        tick; send(6,0,0,0); send(7,1,1,0); // Occupied FIFO admits push and pop.
        check_state(1,3,0); tick;
        if (pin_out !== 0) $fatal(1, "nonempty FIFO bypassed older byte");
        $display("FIFO EDGE CHECKS PASSED");
        $finish;
    end
endmodule
