`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
`ifndef QUESTA_STANDALONE
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end
`endif

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg spi_checking = 0, target_miso = 0;
  reg jtag_checking = 0, tap_tdo = 0;
  wire target_miso_delayed;
  assign #315 target_miso_delayed = target_miso;
  reg tap_tdo_delayed = 0;
  always @(tap_tdo) tap_tdo_delayed <= #315 tap_tdo;
  reg i2c_checking = 0, target_sda_low = 0, target_scl_low = 0;
  reg ps2_active = 0, ps2_echo_active = 0;
  wire bus_sda, bus_scl;
  wire sda_released = !(uio_oe[3] || target_sda_low);
  wire scl_released = !(uio_oe[2] || target_scl_low);
  // Sink immediately. Pull-ups take two falling clock samples to reach
  // logic high (75 ns for a release on a rising engine edge).
  reg [1:0] sda_rise = 3, scl_rise = 3;
  always @(negedge clk or negedge sda_released)
    if (!sda_released) sda_rise <= 0; else sda_rise <= {sda_rise[0], 1'b1};
  always @(negedge clk or negedge scl_released)
    if (!scl_released) scl_rise <= 0; else scl_rise <= {scl_rise[0], 1'b1};
  assign bus_sda = sda_rise[1];
  assign bus_scl = scl_rise[1];
  reg p7_feedback = 0;
  always @(negedge clk) p7_feedback <= uio_oe[7] && uio_out[7];
  wire serial_input = jtag_checking ? tap_tdo_delayed
                    : spi_checking ? target_miso_delayed : uio_in[2];
  wire [7:0] protocol_inputs = (i2c_checking || ps2_active || ps2_echo_active) ? {p7_feedback, uio_in[6:4], bus_sda, bus_scl, uio_in[1:0]}
                           : {uio_in[7:3], serial_input, uio_in[1:0]};

  tt_um_davis_lester_protocol_emulator user_project (
      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (protocol_inputs),
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

  `include "engine_checks.vh"
endmodule
