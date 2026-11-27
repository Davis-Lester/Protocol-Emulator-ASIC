// Shared pin-level driver for the official RTL/GL jobs and Questa.
// The reference traces use 1 MHz SPI. The asynchronous test uses 503 ns halves.
reg start_tests = 0;
reg tests_done = 0;
reg capture = 0;
reg async_host = 0;
reg was_running = 0;
integer trace_file, trace_cycle;
reg [23:0] program_words [0:6];
reg [23:0] uart_words [0:12];
always #25 clk = ~clk;

// Row zero is the edge that accepted START. First instruction retires on row 1.
always @(negedge clk) begin
    if (capture && (uo_out[1] || was_running)) begin
        $fdisplay(trace_file, "%0d,%02h,%02h,%0d,%0d",
                  trace_cycle, uio_out, uio_oe, uo_out[1], uo_out[2]);
        trace_cycle = trace_cycle + 1;
    end
    was_running = uo_out[1];
end

task fail;
    input [8*96-1:0] reason;
    begin
        $display("ENGINE FAIL: %0s at time %0t", reason, $time);
        $finish;
    end
endtask

task wait_half;
    begin
        if (async_host) #503;
        else repeat (10) @(negedge clk);
    end
endtask

task select_host;
    begin
        ui_in = 0;
        wait_half;
    end
endtask

task release_host;
    begin
        ui_in = 4;
        wait_half;
        if (uo_out[0] !== 0) fail("MISO active after CS release");
    end
endtask

task spi_bit;
    input mosi;
    output miso;
    begin
        ui_in[1] = mosi;
        wait_half;
        miso = uo_out[0];
        ui_in[0] = 1;
        wait_half;
        ui_in[0] = 0;
    end
endtask

task exchange;
    input [7:0] send_byte, expect_byte;
    integer bit_no;
    reg [7:0] got;
    begin
        for (bit_no=7; bit_no>=0; bit_no=bit_no-1)
            spi_bit(send_byte[bit_no], got[bit_no]);
        if (got !== expect_byte) begin
            $display("host sent %02h expected %02h got %02h", send_byte, expect_byte, got);
            fail("SPI response");
        end
    end
endtask

task command;
    input [7:0] op, size;
    input [23:0] data;
    input [7:0] expected;
    integer index;
    begin
        select_host;
        exchange(op, 0);
        exchange(size, 0);
        for (index=size; index>0; index=index-1)
            exchange(data >> (8*(index-1)), 0);
        exchange(0, expected);
        exchange(0, 0);  // response length
        exchange(0, 0);  // clocks beyond response
        release_host;
    end
endtask

task fifo_status;
    input [7:0] flags, code, pc, tx_count, rx_count;
    begin
        select_host;
        exchange(0, 0); exchange(0, 0);  // STATUS, length zero
        exchange(0, 0); exchange(0, 6);  // acceptance, six response bytes
        exchange(0, 1); exchange(0, flags | (tx_count < 4 ? 8'h08 : 0) | (rx_count != 0 ? 8'h04 : 0)); exchange(0, code);
        exchange(0, pc); exchange(0, tx_count); exchange(0, rx_count);
        exchange(0, 0);
        release_host;
    end
endtask

task status_check;
    input [7:0] flags, code, pc;
    begin fifo_status(flags,code,pc,0,0); end
endtask

task reset_chip;
    begin
        ena = 1;
        rst_n = 0;
        ui_in = 4;
        wait_half;
        if ({uo_out,uio_oe,uio_out} !== 24'b0) fail("unsafe asserted reset");
        rst_n = 1;
        wait_half;
        if ({uo_out,uio_oe,uio_out} !== 24'h10_00_00) fail("unsafe reset state");
    end
endtask

task illegal_program;
    input [23:0] word;
    begin
        command(2,1,1,0); command(3,3,word,0); command(4,0,0,0);
        command(6,0,0,0);
        status_check(2,1,0);
        if ({uio_out,uio_oe} !== 0) fail("fault did not release pins");
        command(6,0,0,3); command(9,0,0,0);
    end
endtask

// Drive the wire with a transmitter clock independent of the ASIC clock.
task uart_frame;
    input [7:0] data;
    input stop_level;
    input integer bit_ns;
    integer b;
    begin
        uio_in[2] = 0;
        #(bit_ns);
        for (b=0; b<8; b=b+1) begin
            uio_in[2] = data[b];
            #(bit_ns);
        end
        uio_in[2] = stop_level;
        #(bit_ns);
        uio_in[2] = 1;
    end
endtask

task read_rx;
    input [7:0] expected;
    begin
        select_host;
        exchange(8,0); exchange(0,0);
        exchange(0,0); exchange(0,1); exchange(0,expected);
        release_host;
    end
endtask

`include "spi_controller_checks.vh"
`include "i2c_controller_checks.vh"
`include "jtag_controller_checks.vh"
`include "ps2_keyboard_checks.vh"

integer i;
reg discard_bit;
initial begin
    clk = 0;
    rst_n = 0;
    ena = 0;
    ui_in = 4;
    uio_in = 0;
`ifndef QUESTA_STANDALONE
    wait (start_tests);
`endif
    // Release selected reset on either side of a rising edge. The independent
    // 1006 ns SCK period walks the sampling phase through each STATUS frame.
    async_host = 1;
    for (i=0; i<2; i=i+1) begin
        @(negedge clk);
        #7 ena = 1;
        rst_n = 0;
        repeat (2) @(negedge clk);
        if (i == 0) #24.5;
        else #25.5;
        rst_n = 1;
        #400;
        status_check(0,0,0);
        command(8'ha5,1,24'h000096,1); // mixed MOSI bits, unsupported opcode
        ena = 0;
        wait_half;
    end
    async_host = 0;
    reset_chip;
    status_check(0,0,0);
    command(6,0,0,3);          // START without image
    command(2,1,0,4); command(2,1,65,4);
    command(2,2,7,2); command(8,0,0,6);
    command(2,1,7,0);
    select_host;                // abort WRITE_WORD after 2 bytes + 3 bits
    exchange(3,0); exchange(3,0); exchange(8'hff,0); exchange(8'hff,0);
    repeat (3) spi_bit(1, discard_bit);
    release_host;
    command(4,0,0,3);
    $readmemh("sim_build/pulse.hex", program_words);
    for (i=0; i<7; i=i+1) command(3,3,program_words[i],0);
    command(3,3,24'hffffff,3); // excess word
    command(4,0,0,0);
    trace_cycle = 0;
    trace_file = $fopen("sim_build/pulse-rtl.csv", "w");
    if (!trace_file) fail("cannot create RTL trace");
    $fdisplay(trace_file,"cycle,out,oe,running,fault");
    capture = 1;
    command(6,0,0,0);
    capture = 0;
    $fclose(trace_file);
    if (trace_cycle != 29) fail("pulse run length");
    status_check(0,0,6);
    if ({uio_out,uio_oe} !== 0) fail("HALT did not release pins");

    // Masked OUT and open drain, then long enough to send commands in flight.
    command(5,1,12,0); command(2,1,5,0);
    command(3,3,24'h10ffff,0); command(3,3,24'h100800,0);
    command(3,3,24'h20ffff,0); command(3,3,24'h30ffff,0);
    command(3,3,0,0); command(4,0,0,0); command(6,0,0,0);
    status_check(1,0,3);
    command(2,1,1,3); command(5,1,0,3);
    if ({uio_out,uio_oe} !== 16'hf3fb) fail("mask/open-drain drive");
    command(1,0,0,0);
    if ({uo_out,uio_out,uio_oe} !== 24'h10_00_00) fail("STOP did not release pins");
    command(9,0,0,0); command(6,0,0,0); // CLEAR preserves committed image/OD
    if ({uio_out,uio_oe} !== 16'hf3fb) fail("restart after CLEAR");
    @(negedge clk); #7 ena = 0; #2;
    if ({uo_out,uio_out,uio_oe} !== 0) fail("deselect did not release pins");
    wait_half; ena = 1; wait_half;
    command(6,0,0,0); // disarmed interface remains silent
    if ({uo_out,uio_out,uio_oe} !== 0) fail("reselection without reset");
    reset_chip; command(6,0,0,3);

    illegal_program(24'h300000);  // DELAY zero
    illegal_program(24'h110101);  // reserved OUT operand
    illegal_program(24'hf00000);  // TRAP zero
    command(2,1,64,0);
    for (i=0; i<63; i=i+1) command(3,3,24'h300001,0);
    command(3,3,24'h20ffff,0); command(4,0,0,0);
    command(6,0,0,0); status_check(2,2,64); // full image falls off end
    if ({uio_out,uio_oe} !== 0) fail("PC fault did not release pins");
    reset_chip;
    $readmemh("sim_build/uart_tx.hex", uart_words);
    command(2,1,13,0);
    for (i=0; i<13; i=i+1) command(3,3,uart_words[i],0);
    command(4,0,0,0);
    trace_cycle = 0;
    trace_file = $fopen("sim_build/uart-rtl.csv", "w");
    if (trace_file == 0) fail("cannot create UART trace");
    $fdisplay(trace_file,"cycle,out,oe,running,fault");
    capture = 1;
    command(6,0,0,0);
    repeat (2000) @(negedge clk);
    capture = 0;
    $fclose(trace_file);
    status_check(0,0,12);

    command(7,0,0,2);          // WRITE_TX requires one payload byte.
    command(7,1,24'hc0,0);
    fifo_status(0,0,12,1,0);
    command(9,0,0,0);         // CLEAR drops queued data.
    status_check(0,0,0);
    command(7,1,24'hc1,0);
    reset_chip;               // Reset drops queued data and invalidates the program.
    status_check(0,0,0);

    $readmemh("sim_build/uart_fifo_tx.hex", uart_words);
    command(2,1,13,0);
    for (i=0; i<13; i=i+1) command(3,3,uart_words[i],0);
    command(4,0,0,0);
    command(7,1,24'h96,0); command(7,1,0,0);
    command(7,1,24'hff,0); command(7,1,24'h53,0);
    if (uo_out[4] !== 0) fail("TX_READY asserted when full");
    command(7,1,24'hfe,5);    // Overflow preserves all four entries.
    fifo_status(0,0,0,4,0);
    trace_cycle = 0;
    trace_file = $fopen("sim_build/uart-fifo-rtl.csv", "w");
    if (trace_file == 0) fail("cannot create FIFO UART trace");
    $fdisplay(trace_file,"cycle,out,oe,running,fault");
    capture = 1;
    command(6,0,0,0);
    if (uo_out[4] !== 1) fail("TX_READY stayed low after first pop");
    command(7,1,24'ha9,0);    // Refill the wrapped slot while TX is running.
    repeat (9000) @(negedge clk);
    status_check(1,0,3);      // Waiting at GET_TX with idle high.
    command(7,1,24'h3c,0);    // Simultaneous empty FIFO push and GET_TX.
    repeat (2000) @(negedge clk);
    command(1,0,0,0);
    capture = 0;
    $fclose(trace_file);
    status_check(0,0,3);

    command(2,1,2,0); command(3,3,24'h20ffff,0); command(3,3,24'h800002,0);
    command(4,0,0,0); command(6,0,0,0);
    status_check(2,4,1);      // Bounded GET_TX expired, released active outputs.
    if ({uio_out,uio_oe} !== 0) fail("TX timeout did not release pins");
    reset_chip;
    uio_in[2] = 1;
    $readmemh("sim_build/uart_rx.hex", uart_words);
    command(2,1,13,0);
    for (i=0; i<13; i=i+1) command(3,3,uart_words[i],0);
    command(4,0,0,0); command(6,0,0,0);
    #13 uio_in[2] = 0; #2000 uio_in[2] = 1; #90000;
    fifo_status(1,0,1,0,0); // Short start pulse.
    uart_frame(8'h96,1,8681);
    uart_frame(8'h00,1,8571);
    uart_frame(8'hff,1,8801);
    uart_frame(8'h53,1,8681);
    fifo_status(1,0,1,0,4);
    if (uo_out[3] !== 1 || uio_oe !== 0) fail("RX status or pin direction");
    uart_frame(8'ha5,1,8681); // Full FIFO faults at PUT_RX.
    fifo_status(2,5,11,0,4);
    command(8,1,0,2);
    read_rx(8'h96); read_rx(8'h00); read_rx(8'hff); read_rx(8'h53);
    if (uo_out[3] !== 0) fail("RX_VALID after draining");
    command(8,0,0,6);
    command(9,0,0,0); command(6,0,0,0);
    uart_frame(8'h3c,1,8681);
    uart_frame(8'h81,0,8681); // Bad stop is rejected, previous byte retained.
    fifo_status(2,8'h80,10,0,1);
    read_rx(8'h3c);
    command(9,0,0,0); command(6,0,0,0);
    uart_frame(8'ha9,1,8681);
    read_rx(8'ha9);
    $display("UART RX PIN CHECKS PASSED");
    run_spi_controller;
    run_i2c_controller;
    run_jtag_controller;
    run_ps2_keyboard;
    $display("ENGINE PIN CHECKS PASSED");
    tests_done = 1;
`ifdef QUESTA_STANDALONE
    $finish;
`endif
end
