module de0(

    // Reset
    input              RESET_N,

    // Clocks
    input              CLOCK_50,
    input              CLOCK2_50,
    input              CLOCK3_50,
    inout              CLOCK4_50,

    // DRAM
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

    // GPIO
    inout       [35:0] GPIO_0,
    inout       [35:0] GPIO_1,

    // 7-Segment LED
    output      [6:0]  HEX0,
    output      [6:0]  HEX1,
    output      [6:0]  HEX2,
    output      [6:0]  HEX3,
    output      [6:0]  HEX4,
    output      [6:0]  HEX5,

    // Keys
    input       [3:0]  KEY,

    // LED
    output      reg [9:0]  LEDR,

    // PS/2
    inout              PS2_CLK,
    inout              PS2_DAT,
    inout              PS2_CLK2,
    inout              PS2_DAT2,

    // SD-Card
    output             SD_CLK,
    inout              SD_CMD,
    inout       [3:0]  SD_DATA,

    // Switch
    input       [9:0]  SW,

    // VGA
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

assign GPIO_1[33] = RESET_N; // CH_PD (ChipEnabled)
// assign GPIO_1[29] = 1'b1; // VCC
// assign GPIO_1[34] = 1'b0; // GND

// LED OFF
assign HEX0 = 7'b1111111;
assign HEX1 = 7'b1111111;
assign HEX2 = 7'b1111111;
assign HEX3 = 7'b1111111;
assign HEX4 = 7'b1111111;
assign HEX5 = 7'b1111111;

// Генерация частот
wire locked;
wire clock_25;

de0pll unit_pll
(
    .clkin     (CLOCK_50),
    .m25       (clock_25),
    .locked    (locked)
);


reg  [7:0] tx_byte = 0;
reg        tx_send = 0;
wire [7:0] rx_byte;
wire       rx_ready;

reg [3:0]  stage = 0;
reg [3:0]  nbyte = 0;

always @(posedge clock_25) begin

    if (KEY[0] == 0) begin

        case (stage)

            0: begin stage <= stage + 1; tx_send <= 1; tx_byte <= 8'h41; end // A
            2: begin stage <= stage + 1; tx_send <= 1; tx_byte <= 8'h54; end // T
            4: begin stage <= stage + 1; tx_send <= 1; tx_byte <= 8'h0D; end // 13 \r
            6: begin stage <= stage + 1; tx_send <= 1; tx_byte <= 8'h0A; end // 10 \n
            8: begin if (rx_ready) begin stage <= 15; end end
            15: begin /* null */ end
            default: begin tx_send <= 0; if (tx_ready) stage <= stage + 1; end

        endcase

        if (rx_ready) begin

            if (nbyte == SW[3:0]) LEDR[7:0] <= rx_byte;
            nbyte <= nbyte + 1;

        end

    end

end

uart UART
(
    .reset_n  (locked),

    // Физический интерфейс
    .clock25  (clock_25),
    .rx       (GPIO_1[35]), // TX на модуле
    .tx       (GPIO_1[28]), // RX на модуле

    // Прием
    .rx_ready (rx_ready),
    .rx_byte  (rx_byte),

    // Отсылка
    .tx_byte  (tx_byte),
    .tx_send  (tx_send),
    .tx_ready (tx_ready)
);

endmodule

