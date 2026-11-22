// A peripheral on the emulated pins. Observe halfway between engine edges,
// then allow 315 ns for target clock-to-output before MISO reaches the DUT.
reg [1:0] controller_mode;
wire cpol = controller_mode[1], cpha = controller_mode[0];
wire cs_n = uio_out[0], mosi = uio_out[1], sck = uio_out[3];
reg [7:0] controller_tx [0:5], target_tx [0:5];
reg spi_driving, spi_stopping, prev_cs, prev_sck, prev_mosi;
integer frames, edges, samples;
time last_cs, last_sck, last_mosi;

always @(negedge clk) begin
    if (spi_checking) begin
        if (uio_oe === 0) begin
            if (spi_driving && !(spi_stopping && prev_cs))
                fail("controller released pins during transfer or idle wait");
            spi_driving = 0;
        end else if (uio_oe !== 8'h0b) begin
            fail("controller must drive only CS, MOSI and SCK");
        end else if (!spi_driving) begin
            if (cs_n !== 1 || sck !== cpol) fail("controller enabled with bus active");
            spi_driving = 1;
            last_cs = $time;
            last_mosi = $time;
        end else begin
            if (cs_n !== prev_cs) begin
                if (sck !== cpol || sck !== prev_sck) fail("SCK active at CS edge");
                if (!cs_n) begin
                    if ($time - last_cs < 500 || frames >= 6) fail("CS idle time or extra frame");
                    edges = 0;
                    samples = 0;
                    if (!cpha) target_miso = target_tx[frames][7];
                end else begin
                    if (edges != 16 || samples != 8 || $time - last_sck < 500)
                        fail("CS hold time or incomplete byte");
                    frames = frames + 1;
                    target_miso = 0;
                end
                last_cs = $time;
            end
            if (mosi !== prev_mosi) begin
                if (cs_n !== 0 || sck !== (cpol ^ cpha))
                    fail("MOSI changed outside launch half-cycle");
                last_mosi = $time;
            end
            if (sck !== prev_sck) begin
                if (cs_n !== 0 || edges >= 16) fail("unexpected SCK edge");
                if (edges == 0) begin
                    if ($time - last_cs < 500) fail("CS setup time");
                end else if ($time - last_sck != 500) fail("incorrect SCK half-period");
                edges = edges + 1;
                last_sck = $time;
                if ((sck != cpol) != cpha) begin
                    if ($time - last_mosi < 400 || mosi !== controller_tx[frames][7-samples]) begin
                        $display("SPI mode %0d frame %0d bit %0d MOSI=%b", controller_mode, frames, samples, mosi);
                        fail("controller MOSI bit or setup time");
                    end
                    samples = samples + 1;
                end else if (samples < 8) begin
                    target_miso = target_tx[frames][7-samples];
                end
            end
        end
        prev_cs = cs_n;
        prev_sck = sck;
        prev_mosi = mosi;
    end
end

task run_spi_controller;
    integer images, mode, n, length;
    reg [23:0] word;
    begin
        controller_tx[0] = 8'h96; controller_tx[1] = 8'h00; controller_tx[2] = 8'hff;
        controller_tx[3] = 8'h53; controller_tx[4] = 8'ha9; controller_tx[5] = 8'h3c;
        target_tx[0] = 8'h69; target_tx[1] = 8'hd2; target_tx[2] = 8'h00;
        target_tx[3] = 8'hff; target_tx[4] = 8'h35; target_tx[5] = 8'h81;
        images = $fopen("sim_build/spi_programs.hex", "r");
        if (!images) fail("cannot open assembled SPI programs");
        for (mode = 0; mode < 4; mode = mode + 1) begin
            reset_chip;
            if ($fscanf(images, "%h", length) != 1 || length < 1 || length > 64)
                fail("invalid SPI program length");
            command(2, 1, length[23:0], 0);
            for (n = 0; n < length; n = n + 1) begin
                if ($fscanf(images, "%h", word) != 1) fail("short SPI program");
                command(3, 3, word, 0);
            end
            command(4, 0, 0, 0);
            for (n = 0; n < 4; n = n + 1) command(7, 1, {16'b0, controller_tx[n]}, 0);
            command(7, 1, 24'hee, 5);  // Fifth queued byte is rejected before START.
            controller_mode = mode[1:0];
            spi_driving = 0;
            spi_stopping = 0;
            frames = 0;
            spi_checking = 1;
            command(6, 0, 0, 0);
            repeat (1000) @(negedge clk);
            if (frames != 4 || cs_n !== 1 || sck !== cpol || uo_out[3:1] !== 3'b101)
                fail("SPI burst or idle while TX empty");

            // Frame five waits to enqueue its reply with CS high. Frame six
            // can start only after the host frees a slot by reading frame one.
            for (n = 4; n < 6; n = n + 1) command(7, 1, {16'b0, controller_tx[n]}, 0);
            if (frames != 5 || cs_n !== 1 || sck !== cpol) fail("RX-full bus stall");
            for (n = 0; n < 6; n = n + 1) read_rx(target_tx[n]);
            command(8, 0, 0, 6);
            if (frames != 6 || uo_out[3:1] !== 3'b001) fail("SPI FIFO drain");
            spi_stopping = 1;
            command(1, 0, 0, 0);
            if ({uio_oe, uio_out, uo_out[2:1]} !== 0) fail("SPI STOP pin release");
            spi_checking = 0;
            $display("SPI CONTROLLER MODE %0d PASSED (6 full-duplex frames)", mode);
        end
        $fclose(images);
    end
endtask
