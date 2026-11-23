// Independent addressed target on resolved open-drain wires. Observe the bus
// itself so an SDA transition during SCL high decodes as START or STOP.
localparam I2C_WRITE = 0, REGISTER_READ = 1, DIRECT_READ = 2, LONG_READ = 3;
localparam NO_STRETCH = 0, STRETCH_DATA = 1, HOLD_CLOCK = 2, STRETCH_ACK = 3;
integer bus_rate, packet, nack_byte, stretch_mode;
integer starts_seen, stops_seen, byte_index, bit_slot, stretch_clocks;
integer reads_begin, bytes_expected, count_periods;
reg [7:0] expected_wire [0:6];
reg [7:0] wire_byte;
reg prev_sda, prev_scl, bus_active, stretched;
time first_period, last_clock_edge, last_rise, last_data_edge, last_start, last_stop;

always @(bus_sda or bus_scl) begin
    if (i2c_checking) begin
        if (bus_sda != prev_sda) begin
            if (bus_scl && prev_scl) begin
                if (bus_sda == 0) begin
                    if (starts_seen == 0) begin
                        if ($time - last_stop < (bus_rate == 100 ? 4700 : 1300))
                            fail("I2C bus-free interval");
                    end else if (packet != REGISTER_READ || starts_seen != 1 || byte_index != 2 ||
                                 bit_slot != 1 || !bus_active ||
                                 $time - last_rise < (bus_rate == 100 ? 4700 : 600))
                        fail("unexpected or early repeated START");
                    bus_active = 1;
                    starts_seen = starts_seen + 1;
                    bit_slot = 0;
                    last_start = $time;
                end else begin
                    if (!bus_active || byte_index != bytes_expected || bit_slot != 1 ||
                        $time - last_rise < (bus_rate == 100 ? 4000 : 600))
                        fail("I2C unexpected STOP or STOP setup time");
                    bus_active = 0;
                    stops_seen = stops_seen + 1;
                    last_stop = $time;
                end
            end
            last_data_edge = $time;
        end
        if (bus_active && bus_scl != prev_scl) begin
            if (bus_scl) begin
                if ($time - last_clock_edge < (bus_rate == 100 ? 4700 : 1300))
                    fail("I2C SCL low time");
                if ($time - last_data_edge < (bus_rate == 100 ? 250 : 100))
                    fail("I2C SDA setup time");
                bit_slot = bit_slot + 1;
                if (bit_slot >= 2 && bit_slot <= 8 && stretch_mode == NO_STRETCH) begin
                    if ($time - last_rise < (bus_rate == 100 ? 10000 : 2500) ||
                        $time - last_rise > (bus_rate == 100 ? 10300 : 2800))
                        fail("I2C data bit rate");
                    first_period = $time - last_rise;
                    count_periods = count_periods + 1;
                end
                last_rise = $time;
                if (bit_slot <= 8) begin
                    wire_byte = {wire_byte[6:0], bus_sda};
                    if (byte_index >= reads_begin && byte_index < bytes_expected && uio_oe[3])
                        fail("controller drove a target data bit");
                    if (bit_slot == 8 &&
                        (byte_index >= bytes_expected || wire_byte !== expected_wire[byte_index])) begin
                        $display("I2C byte %0d got %02h", byte_index, wire_byte);
                        fail("I2C target decoded incorrect data or address");
                    end
                end else if (bit_slot == 9) begin
                    if (byte_index < reads_begin) begin
                        if (uio_oe[3] || bus_sda !== (byte_index == nack_byte))
                            fail("I2C target ACK ownership or level");
                    end else if (target_sda_low || bus_sda !== (byte_index == bytes_expected-1))
                        fail("I2C controller must ACK intermediate bytes and NACK the last");
                end else fail("extra clock in I2C byte");
            end else begin
                if (bit_slot == 0) begin
                    if ($time - last_start < (bus_rate == 100 ? 4000 : 600))
                        fail("I2C START hold");
                end else if ($time - last_rise < (bus_rate == 100 ? 4000 : 600))
                    fail("I2C SCL high time");

                // A stretching receiver may retain SDA after ACK until ready.
                if (stretch_mode == STRETCH_ACK && byte_index == 0 && bit_slot == 9) begin
                    target_scl_low = 1;
                    stretched = 1;
                end
                if (bit_slot == 9) begin
                    byte_index = byte_index + 1;
                    bit_slot = 0;
                end
                if (bit_slot == 8)
                    target_sda_low = byte_index < reads_begin && byte_index != nack_byte;
                else if (byte_index >= reads_begin && byte_index < bytes_expected)
                    target_sda_low = !expected_wire[byte_index][7-bit_slot];
                else target_sda_low = (stretch_mode == STRETCH_ACK && target_scl_low);
                if ((stretch_mode == STRETCH_DATA || stretch_mode == HOLD_CLOCK) && !stretched && bit_slot == 3 &&
                    byte_index == (packet == DIRECT_READ ? reads_begin : 0)) begin
                    target_scl_low = 1;
                    stretched = 1;
                end
            end
            last_clock_edge = $time;
        end
        prev_scl = bus_scl;
        prev_sda = bus_sda;
    end
end

always @(negedge clk) begin
    if (i2c_checking) begin
        if ((uio_oe & 8'h73) !== 0 || (uio_out & uio_oe & 8'h0c) !== 0)
            fail("I2C bus must be open drain; reserved pins must be released");
        if (target_scl_low) begin
            if (stretch_clocks > 0 && uio_oe[2]) fail("controller advanced under stretch");
            if (!uio_oe[2]) stretch_clocks = stretch_clocks + 1;
            if (stretch_mode == STRETCH_ACK && stretch_clocks == 130) target_sda_low = 0;
            if ((stretch_mode == STRETCH_DATA || stretch_mode == STRETCH_ACK) && stretch_clocks == 140)
                target_scl_low = 0;
        end
    end
end

reg [7:0] packets [0:31];
integer packet_length [0:3];

task check_i2c_transaction;
    input integer which, nack_at, stretch;
    integer n, clocks, rx_bytes, drained, preload;
    reg [7:0] code;
    begin
        command(9,0,0,0);
        packet = which;
        reads_begin = which == I2C_WRITE ? 2 : (which == REGISTER_READ ? 3 : 1);
        bytes_expected = which == REGISTER_READ ? 5 : (which == LONG_READ ? 7 : 2);
        expected_wire[0] = which >= DIRECT_READ ? 8'ha7 : 8'ha6;
        expected_wire[1] = which >= DIRECT_READ ? 8'h16 : 8'h5a;
        expected_wire[2] = 8'ha7;
        expected_wire[3] = 8'h96;
        expected_wire[4] = 8'h3b;
        expected_wire[5] = 8'h00;
        expected_wire[6] = 8'hff;
        nack_byte = nack_at;
        if (nack_byte >= 0) bytes_expected = nack_byte + 1;
        stretch_mode = stretch;
        code = stretch == HOLD_CLOCK ? 3 : (nack_at >= 0 ? 8'h81 : 0);
        starts_seen = 0;
        stops_seen = 0;
        count_periods = 0;
        byte_index = 0;
        bit_slot = 0;
        bus_active = 0;
        stretched = 0;
        stretch_clocks = 0;
        prev_scl = bus_scl;
        prev_sda = bus_sda;
        last_stop = $time;
        i2c_checking = 1;
        // Queue at most four bytes. The remaining bytes cross the host port
        // while the program is executing, including long clock-low FIFO waits.
        preload = packet_length[which] < 4 ? packet_length[which] : 4;
        if (which == I2C_WRITE && nack_at < 0 && stretch == NO_STRETCH) preload = 0;
        for (n=0; n<preload; n=n+1) command(7,1,{16'b0,packets[which*8+n]},0);
        command(6,0,0,0);
        if (preload == 0) begin
            repeat (450) @(negedge clk);
            if (!uo_out[1] || bus_scl || !bus_active || bit_slot != 0 || byte_index != 0)
                fail("I2C TX-empty must hold SCL low before address data");
        end
        for (n=preload; n<packet_length[which] && (nack_at < 0 || n <= 2*nack_at); n=n+1) begin
            clocks = 0;
            while (!uo_out[4] && clocks < 20000) begin @(negedge clk); clocks = clocks + 1; end
            if (!uo_out[4]) fail("I2C TX FIFO did not drain");
            command(7,1,{16'b0,packets[which*8+n]},0);
        end
        drained = 0;
        if (which == LONG_READ) begin
            clocks = 0;
            while ((byte_index != 5 || bit_slot != 8) && clocks < 20000) begin
                @(negedge clk); clocks = clocks + 1;
            end
            repeat (450) @(negedge clk);
            if (!uo_out[1] || !uo_out[3] || bus_scl || byte_index != 5 || bit_slot != 8)
                fail("I2C RX-full must hold SCL low before the ninth clock");
            read_rx(expected_wire[1]);
            read_rx(expected_wire[2]);
            drained = 2;
        end
        clocks = 0;
        while (uo_out[1] && clocks < 20000) begin @(negedge clk); clocks = clocks + 1; end
        repeat (6) @(negedge clk);
        if (uo_out[1] || uo_out[2] !== (code != 0) || uio_oe !== 0)
            fail("I2C final status or pins");
        if (stretch != NO_STRETCH && (!stretched || stretch_clocks < (stretch == HOLD_CLOCK ? 1000 : 140)))
            fail("target clock stretch was not observed");
        if (stretch == HOLD_CLOCK) begin
            if (bus_scl || byte_index != 0 || stops_seen != 0 || starts_seen != 1)
                fail("I2C timeout during held SCL");
        end else if (starts_seen != ((which == REGISTER_READ && (nack_at < 0 || nack_at >= 2)) ? 2 : 1) ||
                     stops_seen != 1 || byte_index != bytes_expected || !bus_sda || !bus_scl)
            fail("I2C completed framing or idle bus");
        if (stretch == NO_STRETCH && count_periods == 0) fail("I2C frequency was not checked");
        // Check status through SPI as software would. The PC is diagnostic.
        select_host;
        exchange(0,0); exchange(0,0); exchange(0,0); exchange(0,6); exchange(0,1);
        rx_bytes = code == 0 ? bytes_expected - reads_begin : 0;
        exchange(0, {4'b0,uo_out[4],(rx_bytes != 0),(code != 0),1'b0});
        exchange(0,code);
        release_host;
        for (n=drained; n<rx_bytes; n=n+1) read_rx(expected_wire[reads_begin+n]);
        if (uo_out[3]) fail("unexpected I2C RX FIFO data");
        i2c_checking = 0;
        target_scl_low = 0;
        target_sda_low = 0;
        $display("I2C %0d kHz packet=%0d NACK index=%0d stretch=%0d passed",bus_rate,which,nack_at,stretch);
    end
endtask

task run_i2c_controller;
    integer images, data_file, image_index, n, j, length, scenario, inject_nack, stretch;
    reg [23:0] word;
    begin
        images = $fopen("sim_build/i2c_programs.hex","r");
        data_file = $fopen("sim_build/i2c_transactions.hex","r");
        if (images == 0 || data_file == 0) fail("cannot open I2C inputs");
        for (j=0; j<4; j=j+1) begin
            if ($fscanf(data_file,"%h",length) != 1 || length < 1 || length > 8)
                fail("invalid I2C transaction length");
            packet_length[j] = length;
            for (n=0; n<length; n=n+1) begin
                if ($fscanf(data_file,"%h",word) != 1) fail("short I2C transaction");
                packets[j*8+n] = word[7:0];
            end
        end
        $fclose(data_file);
        for (image_index=0; image_index<4; image_index=image_index+1) begin
            reset_chip;
            bus_rate = image_index < 2 ? 100 : 400;
            if ($fscanf(images,"%h",length) != 1 || length < 1 || length > 64)
                fail("invalid I2C image length");
            command(2,1,length[23:0],0);
            for (n=0; n<length; n=n+1) begin
                if ($fscanf(images,"%h",word) != 1) fail("short I2C image");
                command(3,3,word,0);
            end
            command(4,0,0,0);
            command(5,1,12,0);
            // Use one common driver for each row of the test matrix.
            for (j=0; j<(image_index % 2 == 0 ? 5 : 4); j=j+1) begin
                if (image_index % 2 == 0) begin
                    case (j)
                        0: begin scenario = I2C_WRITE; inject_nack = 0;  stretch = NO_STRETCH; end
                        1: begin scenario = I2C_WRITE; inject_nack = 1;  stretch = NO_STRETCH; end
                        2: begin scenario = I2C_WRITE; inject_nack = -1; stretch = HOLD_CLOCK; end
                        3: begin scenario = I2C_WRITE; inject_nack = -1; stretch = STRETCH_ACK; end
                        4: begin scenario = I2C_WRITE; inject_nack = -1; stretch = NO_STRETCH; end
                    endcase
                end else begin
                    case (j)
                        0: begin scenario = REGISTER_READ; inject_nack = 2;  stretch = NO_STRETCH; end
                        1: begin scenario = REGISTER_READ; inject_nack = -1; stretch = NO_STRETCH; end
                        2: begin scenario = DIRECT_READ; inject_nack = -1; stretch = STRETCH_DATA; end
                        3: begin scenario = LONG_READ; inject_nack = -1; stretch = NO_STRETCH; end
                    endcase
                end
                check_i2c_transaction(scenario, inject_nack, stretch);
            end
            $display("I2C %0d kHz measured data-bit period %0d ns",bus_rate,first_period);
        end
        $fclose(images);
        $display("I2C CONTROLLER PIN CHECKS PASSED");
    end
endtask
