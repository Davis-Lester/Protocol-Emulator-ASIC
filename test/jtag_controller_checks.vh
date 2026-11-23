// Synthetic target with a four-bit IR, a 13-bit read/write DR and BYPASS.
// Rising edges capture/shift. Falling edges launch TDO and update registers.
localparam JT_RESET=0, JT_IDLE=1, JT_SELECT_DR=2, JT_CAPTURE_DR=3, JT_SHIFT_DR=4,
           JT_EXIT1_DR=5, JT_PAUSE_DR=6, JT_EXIT2_DR=7, JT_UPDATE_DR=8,
           JT_SELECT_IR=9, JT_CAPTURE_IR=10, JT_SHIFT_IR=11, JT_EXIT1_IR=12,
           JT_PAUSE_IR=13, JT_EXIT2_IR=14, JT_UPDATE_IR=15;
reg [3:0] tap_state, tap_ir, tap_ir_shift;
reg [12:0] tap_data, tap_shift;
reg tap_bypass;
wire jt_tms = uio_out[0], jt_tdi = uio_out[1], jt_tck = uio_out[3];
integer tap_edges, tap_ir_updates, tap_data_updates;
time jt_rise, jt_fall, jt_input_change;

always @(jt_tms or jt_tdi) begin
    if (jtag_checking && uio_oe == 8'h0b) begin
        if (jt_tck) fail("JTAG inputs changed during TCK high");
        jt_input_change = $time;
    end
end

always @(posedge jt_tck) begin
    if (jtag_checking) begin
        if (uio_oe !== 8'h0b || $time-jt_input_change < 300 || $time-jt_fall < 500)
            fail("JTAG direction, low time or input setup");
        jt_rise = $time;
        if (tap_edges < 6 && jt_tms !== (tap_edges < 5)) fail("JTAG initial reset sequence");
        tap_edges = tap_edges + 1;
        case (tap_state)
            JT_RESET: tap_state = jt_tms ? JT_RESET : JT_IDLE;
            JT_IDLE: tap_state = jt_tms ? JT_SELECT_DR : JT_IDLE;
            JT_SELECT_DR: tap_state = jt_tms ? JT_SELECT_IR : JT_CAPTURE_DR;
            JT_CAPTURE_DR: begin
                tap_bypass = 0;
                tap_shift = tap_data;
                tap_state = jt_tms ? JT_EXIT1_DR : JT_SHIFT_DR;
            end
            JT_SHIFT_DR: begin
                if (tap_ir == 4'h2) tap_shift = {jt_tdi,tap_shift[12:1]};
                else tap_bypass = jt_tdi;
                tap_state = jt_tms ? JT_EXIT1_DR : JT_SHIFT_DR;
            end
            JT_EXIT1_DR: tap_state = jt_tms ? JT_UPDATE_DR : JT_PAUSE_DR;
            JT_PAUSE_DR: tap_state = jt_tms ? JT_EXIT2_DR : JT_PAUSE_DR;
            JT_EXIT2_DR: tap_state = jt_tms ? JT_UPDATE_DR : JT_SHIFT_DR;
            JT_UPDATE_DR: tap_state = jt_tms ? JT_SELECT_DR : JT_IDLE;
            JT_SELECT_IR: tap_state = jt_tms ? JT_RESET : JT_CAPTURE_IR;
            JT_CAPTURE_IR: begin
                tap_ir_shift = 4'h5;
                tap_state = jt_tms ? JT_EXIT1_IR : JT_SHIFT_IR;
            end
            JT_SHIFT_IR: begin
                tap_ir_shift = {jt_tdi,tap_ir_shift[3:1]};
                tap_state = jt_tms ? JT_EXIT1_IR : JT_SHIFT_IR;
            end
            JT_EXIT1_IR: tap_state = jt_tms ? JT_UPDATE_IR : JT_PAUSE_IR;
            JT_PAUSE_IR: tap_state = jt_tms ? JT_EXIT2_IR : JT_PAUSE_IR;
            JT_EXIT2_IR: tap_state = jt_tms ? JT_UPDATE_IR : JT_SHIFT_IR;
            JT_UPDATE_IR: tap_state = jt_tms ? JT_SELECT_DR : JT_IDLE;
        endcase
        if (tap_edges == 5 && tap_state != JT_RESET) fail("five clocks did not reset TAP");
    end
end

always @(negedge jt_tck) begin
    if (jtag_checking && uio_oe == 8'h0b) begin
        if ($time-jt_rise != 500) fail("JTAG TCK high pulse");
        jt_fall = $time;
        tap_tdo = 0;
        case (tap_state)
            JT_RESET: tap_ir = 4'hf;
            JT_SHIFT_IR: tap_tdo = tap_ir_shift[0];
            JT_SHIFT_DR: tap_tdo = tap_ir == 4'h2 ? tap_shift[0] : tap_bypass;
            JT_UPDATE_IR: begin
                tap_ir = tap_ir_shift;
                if (tap_ir !== (tap_ir_updates == 0 ? 4'h2 : 4'hf))
                    fail("incorrect selected JTAG instruction");
                tap_ir_updates = tap_ir_updates + 1;
            end
            JT_UPDATE_DR: if (tap_ir == 4'h2) begin
                tap_data = tap_shift;
                if (tap_data !== (tap_data_updates == 0 ? 13'h1791 : 13'h0128))
                    fail("incorrect JTAG data update");
                tap_data_updates = tap_data_updates + 1;
            end
        endcase
    end
end

task run_jtag_controller;
    integer image_fd, vector_fd, reply_fd, words, cycles, n, sent, bit_no;
    reg [23:0] word;
    reg [7:0] reply;
    begin
        reset_chip;
        image_fd = $fopen("sim_build/jtag_program.hex","r");
        vector_fd = $fopen("sim_build/jtag_cycles.hex","r");
        reply_fd = $fopen("sim_build/jtag_replies.hex","w");
        if (image_fd == 0 || vector_fd == 0 || reply_fd == 0) fail("JTAG file open");
        if ($fscanf(image_fd,"%h",words) != 1 || words < 1 || words > 64) fail("JTAG image length");
        command(2,1,words[23:0],0);
        for (n=0;n<words;n=n+1) begin
            if ($fscanf(image_fd,"%h",word) != 1) fail("short JTAG image");
            command(3,3,word,0);
        end
        $fclose(image_fd);
        command(4,0,0,0);
        command(5,1,0,0);
        tap_edges = 0;
        tap_ir_updates = 0;
        tap_data_updates = 0;
        tap_state = JT_PAUSE_DR;
        tap_ir = 4'hf;
        tap_data = 13'h1357;
        jt_fall = $time;
        jt_input_change = $time;
        jtag_checking = 1;
        command(6,0,0,0);
        if (tap_edges != 0 || uio_oe !== 8'h0b || jt_tck !== 0) fail("JTAG empty start");
        if ($fscanf(vector_fd,"%h",cycles) != 1 || cycles < 6) fail("JTAG vector length");
        for (sent=0;sent<6;sent=sent+1) begin
            if ($fscanf(vector_fd,"%h",word) != 1) fail("short JTAG vector");
            command(7,1,word,0);
        end
        if (tap_edges != 5 || jt_tck !== 0) fail("JTAG full RX queue must stall with TCK low");
        for (n=0;n<cycles;n=n+1) begin
            select_host;
            exchange(8,0); exchange(0,0); exchange(0,0); exchange(0,1);
            for (bit_no=7;bit_no>=0;bit_no=bit_no-1) spi_bit(0,reply[bit_no]);
            if (reply[7:1] !== 0) fail("invalid JTAG sample");
            $fdisplay(reply_fd,"%02h",reply);
            release_host;
            if (sent < cycles) begin
                if ($fscanf(vector_fd,"%h",word) != 1) fail("short JTAG vector");
                command(7,1,word,0);
                sent = sent + 1;
            end
        end
        $fclose(vector_fd);
        $fclose(reply_fd);
        if (tap_edges != cycles || tap_state != JT_IDLE || jt_tck !== 0 ||
            tap_ir_updates != 2 || tap_data_updates != 2 || uo_out[3:1] !== 3'b001)
            fail("JTAG completion or FIFO order");
        command(1,0,0,0);
        if (uio_oe !== 0 || uo_out[2:1] !== 0) fail("JTAG STOP release");
        jtag_checking = 0;
        $display("JTAG TAP PIN CHECKS PASSED (%0d clocks)",tap_edges);
    end
endtask
