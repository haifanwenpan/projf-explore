// Project F: Hardware Sprites - Top Hedgehog (Nexys Video)
// (C)2021 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io

`default_nettype none
`timescale 1ns / 1ps

module top_hedgehog (
    input  wire logic clk_100m,         // 100 MHz clock
    input  wire logic btn_rst,          // reset button (active low)
    output      logic hdmi_tx_ch0_p,    // HDMI source channel 0 diff+
    output      logic hdmi_tx_ch0_n,    // HDMI source channel 0 diff-
    output      logic hdmi_tx_ch1_p,    // HDMI source channel 1 diff+
    output      logic hdmi_tx_ch1_n,    // HDMI source channel 1 diff-
    output      logic hdmi_tx_ch2_p,    // HDMI source channel 2 diff+
    output      logic hdmi_tx_ch2_n,    // HDMI source channel 2 diff-
    output      logic hdmi_tx_clk_p,    // HDMI source clock diff+
    output      logic hdmi_tx_clk_n     // HDMI source clock diff-
    );

    // pixel clocks
    logic clk_pix;                  // pixel clock (74.25 MHz)
    logic clk_pix_5x;               // 5x pixel clock for 10:1 DDR SerDes
    logic clk_pix_locked;           // pixel clocks locked?
    clock_gen_pix clock_pix_inst (
        .clk_100m,
        .rst(!btn_rst),             // reset button is active low
        .clk_pix,
        .clk_pix_5x,
        .clk_pix_locked
    );

    // display timings
    localparam CORDW = 11;  // screen coordinate width in bits
    logic [CORDW-1:0] sx, sy;
    logic hsync, vsync, de;
    display_timings_720p timings_720p (
        .clk_pix,
        .rst(!clk_pix_locked),  // wait for pixel clock lock
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de
    );

    // size of screen with and without blanking
    localparam H_RES_FULL = 1650;
    localparam V_RES_FULL = 750;
    localparam H_RES = 1280;
    localparam V_RES = 720;

    logic animate;  // high for one clock tick at start of blanking
    always_comb animate = (sy == V_RES && sx == 0);

    // sprite
    localparam SPR_WIDTH    = 32;   // width in pixels
    localparam SPR_HEIGHT   = 20;   // number of lines
    localparam SPR_SCALE_X  = 8;    // width scale-factor
    localparam SPR_SCALE_Y  = 8;    // height scale-factor
    localparam COLR_BITS    = 4;    // bits per pixel (2^4=16 colours)
    localparam SPR_TRANS    = 9;    // transparent palette entry
    localparam SPR_FRAMES   = 3;    // number of frames in graphic
    localparam SPR_FILE     = "hedgehog_walk.mem";
    localparam SPR_PALETTE  = "hedgehog_palette.mem";

    localparam SPR_PIXELS = SPR_WIDTH * SPR_HEIGHT;
    localparam SPR_DEPTH  = SPR_PIXELS * SPR_FRAMES;
    localparam SPR_ADDRW  = $clog2(SPR_DEPTH);

    logic spr_start, spr_draw;
    logic [COLR_BITS-1:0] spr_pix;

    // sprite ROM
    logic [COLR_BITS-1:0] spr_rom_data;
    logic [SPR_ADDRW-1:0] spr_rom_addr, spr_base_addr;
    rom_sync #(
        .WIDTH(COLR_BITS),
        .DEPTH(SPR_DEPTH),
        .INIT_F(SPR_FILE)
    ) spr_rom (
        .clk(clk_pix),
        .addr(spr_base_addr + spr_rom_addr),
        .data(spr_rom_data)
    );

    // draw sprite at position
    localparam SPR_SPEED_X = 4;
    localparam SPR_SPEED_Y = 0;
    logic [CORDW-1:0] sprx, spry;

    // sprite frame selector
    logic [5:0] cnt_anim;  // count from 0-63
    always_ff @(posedge clk_pix) begin
        if (animate) begin
            // select sprite frame
            cnt_anim <= cnt_anim + 1;
            case (cnt_anim)
                0: spr_base_addr <= 0;
                15: spr_base_addr <= SPR_PIXELS;
                31: spr_base_addr <= 0;
                47: spr_base_addr <= 2 * SPR_PIXELS;
                default: spr_base_addr <= spr_base_addr;
            endcase

            // walk right-to-left (correct position for screen width)
            sprx <= (sprx > SPR_SPEED_X) ? sprx - SPR_SPEED_X :
                                           H_RES_FULL - (SPR_SPEED_X - sprx);
        end
        if (!clk_pix_locked) begin
            sprx <= 0;
            spry <= 320;
        end
    end

    // start sprite in blanking of line before first line drawn
    logic [CORDW-1:0] spry_cor;  // corrected for wrapping
    always_comb begin
        spry_cor = (spry == 0) ? V_RES_FULL - 1 : spry - 1;
        spr_start = (sy == spry_cor && sx == H_RES);
    end

    sprite #(
        .WIDTH(SPR_WIDTH),
        .HEIGHT(SPR_HEIGHT),
        .COLR_BITS(COLR_BITS),
        .SCALE_X(SPR_SCALE_X),
        .SCALE_Y(SPR_SCALE_Y),
        .CORDW(CORDW),
        .H_RES_FULL(H_RES_FULL),
        .ADDRW(SPR_ADDRW)
        ) spr_instance (
        .clk(clk_pix),
        .rst(!clk_pix_locked),
        .start(spr_start),
        .sx,
        .sprx,
        .data_in(spr_rom_data),
        .pos(spr_rom_addr),
        .pix(spr_pix),
        .draw(spr_draw),
        /* verilator lint_off PINCONNECTEMPTY */
        .done()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    // background colour
    logic [11:0] bg_colr;
    always_comb begin
        bg_colr = 12'h260;  // default
        if (sy < 120)      bg_colr = 12'h239;
        else if (sy < 220) bg_colr = 12'h24A;
        else if (sy < 300) bg_colr = 12'h25B;
        else if (sy < 360) bg_colr = 12'h26C;
        else if (sy < 410) bg_colr = 12'h27D;
        else if (sy < 450) bg_colr = 12'h29E;
        else if (sy < 480) bg_colr = 12'h2BF;
    end

    // colour lookup table (ROM)
    localparam CLUT_ENTRIES = 11;
    localparam BPP = 12;  // bits per pixel
    logic [BPP-1:0] clut_colr;
    rom_async #(
        .WIDTH(BPP),
        .DEPTH(CLUT_ENTRIES),
        .INIT_F(SPR_PALETTE)
    ) clut (
        .addr(spr_pix),
        .data(clut_colr)
    );

    // map sprite colour index to palette using CLUT and incorporate background
    logic spr_trans;  // sprite pixel transparent?
    logic [3:0] red_spr, green_spr, blue_spr;  // sprite colour components
    logic [3:0] red_bg,  green_bg,  blue_bg;   // background colour components
    logic [3:0] red, green, blue;              // final colour
    always_comb begin
        spr_trans = (spr_pix == SPR_TRANS);
        {red_spr, green_spr, blue_spr} = clut_colr;
        {red_bg,  green_bg,  blue_bg}  = bg_colr;
        red   = (spr_draw && !spr_trans) ? red_spr   : red_bg;
        green = (spr_draw && !spr_trans) ? green_spr : green_bg;
        blue  = (spr_draw && !spr_trans) ? blue_spr  : blue_bg;
    end

    // DVI signals
    logic [7:0] dvi_red, dvi_green, dvi_blue;
    logic dvi_hsync, dvi_vsync, dvi_de;
    always_ff @(posedge clk_pix) begin
        dvi_hsync <= hsync;
        dvi_vsync <= vsync;
        dvi_de    <= de;
        dvi_red   <= {red,red};  // double up: our output is 8 bit per channel
        dvi_green <= {green,green};
        dvi_blue  <= {blue,blue};
    end

    // TMDS encoding and serialization
    logic tmds_ch0_serial, tmds_ch1_serial, tmds_ch2_serial, tmds_clk_serial;
    dvi_generator dvi_out (
        .clk_pix,
        .clk_pix_5x,
        .rst(!clk_pix_locked),
        .de(dvi_de),
        .data_in_ch0(dvi_blue),
        .data_in_ch1(dvi_green),
        .data_in_ch2(dvi_red),
        .ctrl_in_ch0({dvi_vsync, dvi_hsync}),
        .ctrl_in_ch1(2'b00),
        .ctrl_in_ch2(2'b00),
        .tmds_ch0_serial,
        .tmds_ch1_serial,
        .tmds_ch2_serial,
        .tmds_clk_serial
    );

    // TMDS output pins
    tmds_out tmds_ch0 (.tmds(tmds_ch0_serial),
        .pin_p(hdmi_tx_ch0_p), .pin_n(hdmi_tx_ch0_n));
    tmds_out tmds_ch1 (.tmds(tmds_ch1_serial),
        .pin_p(hdmi_tx_ch1_p), .pin_n(hdmi_tx_ch1_n));
    tmds_out tmds_ch2 (.tmds(tmds_ch2_serial),
        .pin_p(hdmi_tx_ch2_p), .pin_n(hdmi_tx_ch2_n));
    tmds_out tmds_clk (.tmds(tmds_clk_serial),
        .pin_p(hdmi_tx_clk_p), .pin_n(hdmi_tx_clk_n));
endmodule
