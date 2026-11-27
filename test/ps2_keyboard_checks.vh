// Keyboard supplies its own clock. Data changes during the high phase,
// after the rising edge and before the falling edge that samples it.
always @(negedge clk)
    if (ps2_active && uio_oe !== 0) fail("PS/2 receiver drove a pin");

task keyboard_bit;
    input level;
    input integer half_ns;
    begin
        #10000 target_sda_low = !level;
        #(half_ns-10000) target_scl_low = 1;
        #(half_ns) target_scl_low = 0;
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
        #103 target_sda_low = 0;
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

task load_ps2_program;
    input integer fd;
    integer words, iword;
    reg [23:0] insn;
    begin
        if (fd == 0) fail("PS/2 image missing");
        if ($fscanf(fd,"%h",words) != 1 || words < 1 || words > 64) fail("PS/2 image length");
        command(2,1,words[23:0],0);
        for (iword=0;iword<words;iword=iword+1) begin
            if ($fscanf(fd,"%h",insn) != 1) fail("short PS/2 image");
            command(3,3,insn,0);
        end
        $fclose(fd);
        command(4,0,0,0);
    end
endtask

task run_ps2_keyboard;
    integer fd;
    begin
        reset_chip;
        ps2_active = 1;
        fd = $fopen("sim_build/ps2_rx.hex", "r");
        load_ps2_program(fd);
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

// Observe the inhibit and request before START has finished on the SPI bus.
time inhibit_started, data_asserted;
reg saw_inhibit = 0, saw_request = 0, keyboard_owns_data = 0;
always @(posedge uio_oe[2])
    if (ps2_echo_active) begin
        if (saw_inhibit || bus_sda !== 1) fail("unexpected PS/2 host clock inhibit");
        saw_inhibit = 1;
        inhibit_started = $time;
    end
always @(posedge uio_oe[3])
    if (ps2_echo_active && uio_oe[2]) begin
        if (!saw_inhibit || $time - inhibit_started < 100000)
            fail("PS/2 data asserted before 100 us inhibit");
        data_asserted = $time;
    end
always @(negedge uio_oe[2])
    if (ps2_echo_active) begin
        if (!saw_inhibit || data_asserted <= inhibit_started || bus_sda !== 0)
            fail("invalid PS/2 request to send");
        saw_request = 1;
    end
always @(negedge clk)
    if (ps2_echo_active) begin
        if ((uio_oe & 8'hf3) !== 0 || (uio_out & uio_oe) !== 0)
            fail("PS/2 host drove a reserved pin or drove high");
        if (keyboard_owns_data && uio_oe[3] !== 0)
            fail("PS/2 host drove data during keyboard ownership");
    end

// Sample the resolved data at a keyboard-generated rising edge. Also check
// data setup and hold around the pull-up's delayed transition.
task sample_host_bit;
    input integer half_ns;
    output sampled;
    reg setup_level;
    begin
        target_scl_low = 1;
        #(half_ns-3000) setup_level = bus_sda;
        #3000 target_scl_low = 0;
        #500 sampled = bus_sda;
        if (bus_scl !== 1 || setup_level !== sampled) fail("PS/2 host setup or clock release");
        #(half_ns-500);
        if (bus_sda !== sampled) fail("PS/2 host data changed during high clock");
    end
endtask

localparam ECHO_OK = 0, ECHO_NO_ACK = 1, ECHO_STALL = 2, ECHO_SILENT = 3,
           ECHO_NO_CLOCK = 4, ECHO_RETRY = 5;
task run_ps2_echo;
    integer fd, scenario, k, half_ns;
    reg [7:0] received;
    reg sampled;
    begin
        reset_chip;
        ps2_echo_active = 1;
        fd = $fopen("sim_build/ps2_echo.hex", "r");
        load_ps2_program(fd);
        command(5,1,12,0); // CONFIG_OD on clock and data
        for (scenario=ECHO_OK; scenario<=ECHO_RETRY; scenario=scenario+1) begin
            command(9,0,0,0);
            saw_inhibit = 0;
            saw_request = 0;
            data_asserted = 0;
            keyboard_owns_data = 0;
            command(6,0,0,0);
            #150000;
            if (!saw_request || {bus_scl,bus_sda} !== 2'b10) fail("missing PS/2 request");
            half_ns = (scenario == ECHO_RETRY) ? 30000 : 50000;

            if (scenario == ECHO_NO_CLOCK) begin
                // A disconnected keyboard never starts its clock. Preserve
                // the full 15 ms start allowance before the bounded wait expires.
                #14900000;
                if (uo_out[3:1] !== 3'b001 || uio_oe !== 8'h08)
                    fail("PS/2 first-clock timeout too early");
                #1500000;
                ps2_fault(3,0);
                if (uio_oe !== 0) fail("PS/2 absent keyboard retained a driver");
            end else if (scenario == ECHO_STALL) begin
                // Stuck clock on bit zero, while host actively holds the data low.
                target_scl_low = 1;
                #220000;
                ps2_fault(3,0);
                if (uio_oe !== 0) fail("PS/2 timeout retained a driver");
                target_scl_low = 0;
            end else begin
                // Delay the recovery transaction into the long first-clock window.
                if (scenario == ECHO_RETRY) #14000000;
                for (k=0;k<8;k=k+1) begin
                    sample_host_bit(half_ns,sampled);
                    received[k] = sampled;
                end
                if (received !== 8'hee) fail("keyboard received wrong Echo command");
                sample_host_bit(half_ns,sampled);
                if (sampled !== (~^received)) fail("keyboard received wrong command parity");
                sample_host_bit(half_ns,sampled);
                if (sampled !== 1 || uio_oe[3] !== 0) fail("PS/2 stop bit was not released");

                keyboard_owns_data = 1;
                // A high ACK slot models a keyboard which declined the command.
                target_sda_low = (scenario != ECHO_NO_ACK);
                #5000 target_scl_low = 1;
                #(half_ns) target_scl_low = 0;
                #3000 target_sda_low = 0;
                #(half_ns);
                if (scenario == ECHO_NO_ACK) begin
                    ps2_fault(8'h83,0);
                    if (uio_oe !== 0) fail("PS/2 ACK fault retained a driver");
                end else if (scenario == ECHO_SILENT) begin
                    // Host software owns the response deadline while the receiver is idle.
                    #20000000;
                    if (uo_out[3:1] !== 3'b001 || uio_oe !== 0)
                        fail("unexpected byte or status from silent keyboard");
                    command(1,0,0,0); // STOP
                    if (uo_out[3:1] !== 0 || uio_oe !== 0) fail("PS/2 host deadline recovery");
                end else begin
                    keyboard_frame(received,0,1,half_ns);
                    read_rx(8'hee);
                    keyboard_frame(8'h1c,0,1,half_ns);
                    read_rx(8'h1c);
                    if (uo_out[3:1] !== 3'b001) fail("PS/2 Echo status after FIFO drain");
                    command(1,0,0,0);
                end
            end
        end
        ps2_echo_active = 0;
        $display("PS/2 ECHO PIN CHECKS PASSED");
    end
endtask
