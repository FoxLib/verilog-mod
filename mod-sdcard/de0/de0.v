module de0(

      /* Reset */
      input              RESET_N,

      /* Clocks */
      input              CLOCK_50,
      input              CLOCK2_50,
      input              CLOCK3_50,
      inout              CLOCK4_50,

      /* DRAM */
      output             DRAM_CKE,
      output             DRAM_CLK,
      output      [1:0]  DRAM_BA,
      output      [12:0] DRAM_ADDR,
      inout       [15:0] DRAM_DQ,
      output             DRAM_CAS_N,
      output             DRAM_RAS_N,
      output             DRAM_WE_N,
      output             DRAM_CS_N,
      output             DRAM_LDQM,
      output             DRAM_UDQM,

      /* GPIO */
      inout       [35:0] GPIO_0,
      inout       [35:0] GPIO_1,

      /* 7-Segment LED */
      output      [6:0]  HEX0,
      output      [6:0]  HEX1,
      output      [6:0]  HEX2,
      output      [6:0]  HEX3,
      output      [6:0]  HEX4,
      output      [6:0]  HEX5,

      /* Keys */
      input       [3:0]  KEY,

      /* LED */
      output      [9:0]  LEDR,

      /* PS/2 */
      inout              PS2_CLK,
      inout              PS2_DAT,
      inout              PS2_CLK2,
      inout              PS2_DAT2,

      /* SD-Card */
      output             SD_CLK,
      inout              SD_CMD,
      inout       [3:0]  SD_DATA,

      /* Switch */
      input       [9:0]  SW,

      /* VGA */
      output      [3:0]  VGA_R,
      output      [3:0]  VGA_G,
      output      [3:0]  VGA_B,
      output             VGA_HS,
      output             VGA_VS
);

// Z-state
assign DRAM_DQ = 16'hzzzz;
assign GPIO_0  = 36'hzzzzzzzz;
assign GPIO_1  = 36'hzzzzzzzz;

// LED OFF
assign HEX0 = 7'b1111111;
assign HEX1 = 7'b1111111;
assign HEX2 = 7'b1111111;
assign HEX3 = 7'b1111111;
assign HEX4 = 7'b1111111;
assign HEX5 = 7'b1111111;

// LED
assign LEDR[7:0] = pwm_led < 1024 ? errorno : 0;

// MISO: Input Port
assign SD_DATA[0] = 1'bZ;

// ---------------------------------------------------------------------
wire clock_25;  wire clock_50;  wire clock_75;
wire clock_100; wire clock_106;

de0pll u0(

    // Источник тактирования
    .clkin  (CLOCK_50),

    // Производные частоты
    .m25    (clock_25),
    .m50    (clock_50),
    .m75    (clock_75),
    .m100   (clock_100),
    .m106   (clock_106),
    .locked (locked)
);

// ---------------------------------------------------------------------
reg [15:0] pwm_led; always @(posedge clock_25) pwm_led <= pwm_led + 1;
// ---------------------------------------------------------------------

wire [7:0] errorno;

SDCARD u1(

    .clock      (clock_25 & locked),
    .spi_miso   (SD_DATA[0]),           // Входящие данные
    .spi_mosi   (SD_CMD),               // Исходящие
    .spi_sclk   (SD_CLK),               // Тактовая частота
    .spi_cs     (SD_DATA[3]),           // Выбор чипа

    // Отладка
    .errorno    (errorno)
);

endmodule

`include "../sdcard.v"
