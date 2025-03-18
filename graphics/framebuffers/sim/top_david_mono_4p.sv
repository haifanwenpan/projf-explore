// Project F: Framebuffers - Mono David (Verilator SDL)
// (C)2023 Will Green, open source hardware released under the MIT License
// Learn more at https://projectf.io/posts/framebuffers/

`default_nettype none `timescale 1ns / 1ps

module top_david_mono_4p #(
    parameter CORDW = 16
) (  // signed coordinate width (bits)
    input  wire logic               clk_pix,    // pixel clock
    input  wire logic               rst_pix,    // sim reset
    output logic signed [CORDW-1:0] sdl_sx,     // horizontal SDL position
    output logic signed [CORDW-1:0] sdl_sy,     // vertical SDL position
    output logic                    sdl_de,     // data enable (low in blanking interval)
    output logic                    sdl_frame,  // high at start of frame
    output logic        [      7:0] sdl_r0,     // 8-bit red
    output logic        [      7:0] sdl_g0,     // 8-bit green
    output logic        [      7:0] sdl_b0,     // 8-bit blue
    output logic        [      7:0] sdl_r1,     // 8-bit red
    output logic        [      7:0] sdl_g1,     // 8-bit green
    output logic        [      7:0] sdl_b1,     // 8-bit blue
    output logic        [      7:0] sdl_r2,     // 8-bit red
    output logic        [      7:0] sdl_g2,     // 8-bit green
    output logic        [      7:0] sdl_b2,     // 8-bit blue
    output logic        [      7:0] sdl_r3,     // 8-bit red
    output logic        [      7:0] sdl_g3,     // 8-bit green
    output logic        [      7:0] sdl_b3      // 8-bit blue
);

  // display sync signals and coordinates
  logic signed [CORDW-1:0] sx, sy;
  logic de, frame;
  display_480p_4p #(
      .CORDW(CORDW)
  ) display_inst (
      .clk_pix,
      .rst_pix,
      .sx,
      .sy,
      /* verilator lint_off PINCONNECTEMPTY */
      .hsync(),
      .vsync(),
      /* verilator lint_on PINCONNECTEMPTY */
      .de,
      .frame,
      /* verilator lint_off PINCONNECTEMPTY */
      .line ()
      /* verilator lint_on PINCONNECTEMPTY */
  );

  // colour parameters
  localparam CHANW = 4;  // colour channel width (bits)
  localparam COLRW = 3 * CHANW;  // colour width: three channels (bits)
  localparam BG_COLR = 'hF00;  // background colour

  // framebuffer (FB)
  localparam FB_WIDTH = 160;  // framebuffer width in pixels
  localparam FB_HEIGHT = 120;  // framebuffer width in pixels
  localparam FB_PIXELS = FB_WIDTH * FB_HEIGHT;  // total pixels in buffer
  localparam FB_ADDRW = $clog2(FB_PIXELS);  // address width
  localparam FB_DATAW = 1;  // colour bits per pixel
  localparam FB_IMAGE = "../res/david/david_1bit.mem";  // bitmap file
  // localparam FB_IMAGE  = "../../../lib/res/test/test_box_mono_160x120.mem";  // bitmap file

  // pixel read address and colour
  logic [  FB_ADDRW-1:0] fb_addr_read;
  logic [4*FB_DATAW-1:0] fb_colr_read;

  // framebuffer memory
  bram_sdp_4p #(
      .WIDTH (FB_DATAW),
      .DEPTH (FB_PIXELS),
      .INIT_F(FB_IMAGE)
  ) bram_inst (
      .clk_write(clk_pix),
      .clk_read(clk_pix),
      /* verilator lint_off PINCONNECTEMPTY */
      .we(),
      .addr_write(),
      /* verilator lint_on PINCONNECTEMPTY */
      .addr_read(fb_addr_read),
      /* verilator lint_off PINCONNECTEMPTY */
      .data_in(),
      /* verilator lint_on PINCONNECTEMPTY */
      .data_out(fb_colr_read)
  );

  // calculate framebuffer read address for display output
  localparam LAT = 2;  // read_fb+1, BRAM+1
  logic read_fb;
  always_ff @(posedge clk_pix) begin
    read_fb <= (sy >= 0 && sy < FB_HEIGHT && sx >= -LAT && sx < FB_WIDTH / 4 - LAT);
    if (frame) begin  // reset address at start of frame
      fb_addr_read <= 0;
    end else if (read_fb) begin  // increment address in painting area
      fb_addr_read <= fb_addr_read + 4;
    end
  end

  // paint screen
  logic paint_area;  // area of framebuffer to paint
  logic [CHANW-1:0] paint_r0, paint_g0, paint_b0;  // colour channels
  logic [CHANW-1:0] paint_r1, paint_g1, paint_b1;  // colour channels
  logic [CHANW-1:0] paint_r2, paint_g2, paint_b2;  // colour channels
  logic [CHANW-1:0] paint_r3, paint_g3, paint_b3;  // colour channels
  always_comb begin
    paint_area = (sy >= 0 && sy < FB_HEIGHT && sx >= 0 && sx < FB_WIDTH / 4);
    {paint_r0, paint_g0, paint_b0} = paint_area ? {COLRW{fb_colr_read[0+:FB_DATAW]}} : BG_COLR;
    {paint_r1, paint_g1, paint_b1} = paint_area ? {COLRW{fb_colr_read[FB_DATAW+:FB_DATAW]}} : BG_COLR;
    {paint_r2, paint_g2, paint_b2} = paint_area ? {COLRW{fb_colr_read[2*FB_DATAW+:FB_DATAW]}} : BG_COLR;
    {paint_r3, paint_g3, paint_b3} = paint_area ? {COLRW{fb_colr_read[3*FB_DATAW+:FB_DATAW]}} : BG_COLR;
  end

  // display colour: paint colour but black in blanking interval
  logic [4*CHANW-1:0] display_r, display_g, display_b;
  always_comb
    {display_r, display_g, display_b} = (de) ? {{paint_r3, paint_r2, paint_r1, paint_r0}, {paint_g3, paint_g2, paint_g1, paint_g0}, {paint_b3, paint_b2, paint_b1, paint_b0}} : 0;

  // SDL output (8 bits per colour channel)
  always_ff @(posedge clk_pix) begin
    sdl_sx <= sx;
    sdl_sy <= sy;
    sdl_de <= de;
    sdl_frame <= frame;
    sdl_r0 <= {2{display_r[0*CHANW+:CHANW]}};
    sdl_r1 <= {2{display_r[1*CHANW+:CHANW]}};
    sdl_r2 <= {2{display_r[2*CHANW+:CHANW]}};
    sdl_r3 <= {2{display_r[3*CHANW+:CHANW]}};
    sdl_g0 <= {2{display_g[0*CHANW+:CHANW]}};
    sdl_g1 <= {2{display_g[1*CHANW+:CHANW]}};
    sdl_g2 <= {2{display_g[2*CHANW+:CHANW]}};
    sdl_g3 <= {2{display_g[3*CHANW+:CHANW]}};
    sdl_b0 <= {2{display_b[0*CHANW+:CHANW]}};
    sdl_b1 <= {2{display_b[1*CHANW+:CHANW]}};
    sdl_b2 <= {2{display_b[2*CHANW+:CHANW]}};
    sdl_b3 <= {2{display_b[3*CHANW+:CHANW]}};
  end
endmodule
