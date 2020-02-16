// SPI ST7789 display video XY scan core
// AUTHORS=EMARD,MMICKO and Lawrie Griffiths
// LICENSE=BSD

module lcd_video #(
  parameter c_clk_mhz = 25, // MHz clk freq (125 MHz max for st7789)
  parameter c_reset_us = 150000,  // us holding hardware reset
  parameter c_color_bits = 16, // RGB565
  parameter c_x_size = 240,  // pixel X screen size
  parameter c_y_size = 240,  // pixel Y screen size
  parameter c_x_bits = $clog2(c_x_size),
  parameter c_y_bits = $clog2(c_y_size),
  parameter c_clk_polarity = 1, // spi_clk polarity 0:normal (ssd1331), 1:inverted (st7789)
  // file name is relative to directory path in which verilog compiler is running
  // screen can be also XY flipped and/or rotated from this init file
  parameter c_init_file = "st7789_init.mem",
  parameter c_init_size = 38, // bytes in init file
  // although SPI CLK will be stopped during
  // arg parsing and delays, to be on the safe side
  // this will put NOP command at SPI MOSI line
  parameter c_nop = 8'h00 // NOP command from datasheet
) (
  input  wire clk, // SPI display clock rate will be half of this clock rate
  input  wire reset,
  
  output reg  [c_x_bits-1:0] x,
  output reg  [c_y_bits-1:0] y,
  output reg  next_pixel, // 1 when x/y changes
  input  wire [c_color_bits-1:0] color, 

  output wire spi_csn,
  output wire spi_clk, // for SSD1331 invert spi_clk
  output wire spi_mosi,
  output wire spi_dc,
  output wire spi_resn
);


  reg [7:0] c_oled_init[0:c_init_size-1];
  initial begin
    $readmemh(c_init_file, c_oled_init);
  end

  reg [10:0] index;
  reg [7:0] data = c_nop;
  reg dc = 1;
  reg byte_toggle; // alternates data byte for 16-bit mode
  reg init = 1;
  reg [4:0] num_args;
  reg [27:0] delay_cnt = c_clk_mhz*c_reset_us; // initial delay fits 1.3s at 100MHz
  reg [5:0] arg;
  reg delay_set = 0;
  reg [7:0] last_cmd;
  reg resn = 0;
  reg clken = 0;


  // The next byte in the initialisation sequence
  wire [7:0] next_byte = c_oled_init[index[10:4]];

  // Do the initialisation sequence and then start sending pixels
  always @(posedge clk) begin
    if (reset) begin
      delay_cnt <= c_reset_us*c_clk_mhz;
      delay_set <= 0;
      index <= 0;
      init <= 1;
      dc <= 1;
      resn <= 0;
      x <= 0;
      y <= 0;
      byte_toggle <= 0;
      arg <= 1; // after reset, before commands take delay from init sequence
      data <= c_nop;
      clken <= 0;
    end else if (delay_cnt[$bits(delay_cnt)-1] == 0) begin // Delay
      delay_cnt <= delay_cnt - 1;
      resn <= 1;
    end else if (index[10:4] != c_init_size) begin
      index <= index + 1;
      if (index[3:0] == 0) begin // Start of byte
        if (init) begin // Still initialisation
          dc <= 0;
          arg <= arg + 1;
          if (arg == 0) begin // New command
            data <= c_nop; // No NOP
            clken <= 0;
            last_cmd <= next_byte;
          end else if (arg == 1) begin // numArgs and delay_set
            num_args <= next_byte[4:0];
            delay_set <= next_byte[7];
            if (next_byte == 0) arg <= 0; // No args or delay
            data <= last_cmd;
            clken <= 1;
          end else if (arg <= num_args + 1) begin // argument
            data <= next_byte;
            clken <= 1;
            dc <= 1;
            if (arg == num_args + 1 && !delay_set) arg <= 0;
          end else if (delay_set) begin // delay
            delay_cnt <= c_clk_mhz << (next_byte[4:0]); // 2^n us delay
            data <= c_nop;
            clken <= 0;
            delay_set <= 0;
            arg <= 0;
          end
        end else begin // Send pixels and set x,y and next_pixel
          byte_toggle <= ~byte_toggle;
          dc <= 1;
          data <= byte_toggle ? color[7:0] : color[15:8];
          clken <= 1;
          if (byte_toggle) begin
            next_pixel <= 1;
            if (x == c_x_size-1) begin
              x <= 0;
              if (y == c_y_size-1)
                y <= 0;
              else
                y <= y + 1;
            end else x <= x + 1;
          end
        end
      end else begin // Shift out byte
        next_pixel <= 0;
        if (index[0] == 0) data <= { data[6:0], 1'b0 };
      end
    end else begin // Initialisation done, start sending pixels
      init <= 0;
      index[10:4] <= c_init_size - 1;
    end
  end

  assign spi_resn = resn;             // Reset is High, Low, High for first 3 cycles
  assign spi_csn = ~clken;            // Connected to backlight
  assign spi_dc = dc;                 // 0 for commands, 1 for command parameters and data
  assign spi_clk = (index[0] | ~clken) ^ ~c_clk_polarity; // stop clock during arg and delay
  assign spi_mosi = data[7];          // Shift out data

endmodule
