// Keyboard supplies its own clock. Data changes during the high phase,
// after the rising edge and before the falling edge that samples it.
reg ps2_active = 0;
always @(negedge clk)
    if (ps2_active && uio_oe !== 0) fail("PS/2 receiver drove a pin");

task keyboard_bit;
    input level;
    input integer half_ns;
    begin
        #10000 uio_in[3] = level;
        #(half_ns-10000) uio_in[2] = 0;
        #(half_ns) uio_in[2] = 1;
    end
endtask

task keyboard_frame;
    input [7:0] code;
    input parity_error, stop_level;
    input integer half_ns;
    integer k;
    begin
        keyboard_bit(0, half_ns);
        for (k=0; k<8; k=k+1) keyboard_bit(code[k], half_ns);
        keyboard_bit((~^code) ^ parity_error, half_ns);
        keyboard_bit(stop_level, half_ns);
        #103 uio_in[3] = 1;
    end
endtask

// Read STATUS on the host bus, including fault reason and FIFO occupancy.
// The location of the fault in program memory is internal to the image.
task ps2_fault;
    input [7:0] code, queued;
    reg ignored;
    integer k;
    begin
        select_host;
        exchange(0,0); exchange(0,0); exchange(0,0); exchange(0,6);
        exchange(0,1); exchange(0,queued != 0 ? 8'h0e : 8'h0a); exchange(0,code);
        for (k=0;k<8;k=k+1) spi_bit(0,ignored);
        exchange(0,0); exchange(0,queued);
        release_host;
    end
endtask

task run_ps2_keyboard;
    integer fd, words, iword;
    reg [23:0] insn;
    begin
        reset_chip;
        uio_in = 8'h0c;
        ps2_active = 1;
        fd = $fopen("sim_build/ps2_rx.hex", "r");
        if (fd == 0) fail("PS/2 image missing");
        if ($fscanf(fd,"%h",words) != 1 || words < 1 || words > 64) fail("PS/2 image length");
        command(2,1,words[23:0],0);
        for (iword=0;iword<words;iword=iword+1) begin
            if ($fscanf(fd,"%h",insn) != 1) fail("short PS/2 image");
            command(3,3,insn,0);
        end
        $fclose(fd);
        command(4,0,0,0);
        command(6,0,0,0);
        #250013;
        if (uo_out[3:1] !== 3'b001) fail("PS/2 fault or byte during idle");
        keyboard_frame(8'h1c,0,1,30000); // Make, then break prefix and code.
        keyboard_frame(8'hf0,0,1,50000);
        keyboard_frame(8'h1c,0,1,40000);
        keyboard_frame(8'h53,1,1,35000);
        ps2_fault(8'h82,3);
        read_rx(8'h1c); read_rx(8'hf0); read_rx(8'h1c);
        command(9,0,0,0); command(6,0,0,0);
        keyboard_frame(8'h96,0,0,30000);
        ps2_fault(8'h81,0);
        command(9,0,0,0); command(6,0,0,0);
        keyboard_bit(0,35000); // Clock stops before the first data bit.
        #220000;
        ps2_fault(3,0);
        command(9,0,0,0); command(6,0,0,0);
        keyboard_frame(8'ha3,0,1,45000);
        read_rx(8'ha3);
        command(1,0,0,0);
        ps2_active = 0;
        $display("PS/2 KEYBOARD RX PIN CHECKS PASSED");
    end
endtask
