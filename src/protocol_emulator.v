`default_nettype none

module tt_um_davis_lester_protocol_emulator (
    input wire [7:0] ui_in, output wire [7:0] uo_out,
    input wire [7:0] uio_in, output wire [7:0] uio_out, output wire [7:0] uio_oe,
    input wire ena, input wire clk, input wire rst_n
);
    // A deselection disarms the chip, even between system-clock edges.
    // The host must clock reset low while selected to arm it again.
    reg armed;
    always @(posedge clk or negedge ena)
        if (!ena) armed <= 1'b0;
        else if (!rst_n) armed <= 1'b1;

    wire reset_request_n = rst_n && ena && armed;
    (* async_reg = "true" *) reg [1:0] reset_pipe;
    always @(posedge clk or negedge reset_request_n)
        if (!reset_request_n) reset_pipe <= 0;
        else reset_pipe <= {reset_pipe[0], 1'b1};
    wire active = reset_pipe[1];

    wire request;
    wire [7:0] command, length;
    wire [23:0] payload;
    wire [63:0] response;
    wire miso, running, fault;
    wire [7:0] pin_out, pin_oe;

    protocol_spi host (
        .clk(clk), .rst_n(active), .host_pins(ui_in[2:0]), .miso(miso),
        .request(request), .command(command), .length(length), .payload(payload),
        .response(response)
    );
    protocol_core engine (
        .clk(clk), .rst_n(active), .request(request), .command(command),
        .length(length), .payload(payload), .response(response),
        .running(running), .fault(fault), .pin_out(pin_out), .pin_oe(pin_oe)
    );

    wire enabled = active && reset_request_n;
    assign uio_out = enabled ? pin_out : 8'b0;
    assign uio_oe  = enabled ? pin_oe  : 8'b0;
    assign uo_out  = enabled ? {5'b0, fault, running, miso} : 8'b0;
    wire _unused = &{1'b0, uio_in, ui_in[7:3]};
endmodule
