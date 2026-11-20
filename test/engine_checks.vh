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

task status_check;
    input [7:0] flags, code, pc;
    begin
        select_host;
        exchange(0, 0); exchange(0, 0);  // STATUS, length zero
        exchange(0, 0); exchange(0, 6);  // acceptance, six response bytes
        exchange(0, 1); exchange(0, flags); exchange(0, code);
        exchange(0, pc); exchange(0, 0); exchange(0, 0);
        exchange(0, 0);
        release_host;
    end
endtask

task reset_chip;
    begin
        ena = 1;
        rst_n = 0;
        ui_in = 4;
        wait_half;
        rst_n = 1;
        wait_half;
        if ({uo_out,uio_oe,uio_out} !== 24'b0) fail("unsafe reset state");
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
        ena = 0;
        wait_half;
    end
    async_host = 0;
    reset_chip;
    status_check(0,0,0);
    command(6,0,0,3);          // START without image
    command(2,1,0,4); command(2,1,65,4);
    command(2,2,7,2); command(7,1,0,1);
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
    if ({uo_out,uio_out,uio_oe} !== 0) fail("STOP did not release pins");
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
    illegal_program(24'h400000);  // outside milestone ISA
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
    $display("ENGINE PIN CHECKS PASSED");
    tests_done = 1;
`ifdef QUESTA_STANDALONE
    $finish;
`endif
end
