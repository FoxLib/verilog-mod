`timescale 10ns / 1ns
module tb;
// ---------------------------------------------------------------------
reg clock;
reg clock_25;
reg clock_50;

always #0.5 clock    = ~clock;
always #1.0 clock_50 = ~clock_50;
always #1.5 clock_25 = ~clock_25;

initial begin clock = 0; clock_25 = 0; clock_50 = 0; #2000 $finish; end
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end
// ---------------------------------------------------------------------

wire cs;
wire sclk;
reg  miso = 1;
wire mosi;

SDCARD SD(

    .clock      (clock),
    .spi_cs     (cs),
    .spi_sclk   (sclk),
    .spi_miso   (miso),
    .spi_mosi   (mosi)
);

// ---------------------------------------------------------------------
// Эмулятор микроконтроллера SD
// ---------------------------------------------------------------------

reg  [7:0] mk_state  = 0;
reg  [7:0] mk_data_i = 0;
reg  [7:0] mk_data_w = 8'hFF;
reg  [2:0] mk_bit    = 0;
wire [7:0] mk_recv   = {mk_data_i[6:0], mosi};
reg  [5:0] mk_command = 6'h3F;
reg [31:0] mk_arg    = 32'hFFFFFFFF;

// Прием и отсылка байта
always @(posedge sclk) begin

    miso      <=  mk_data_w[7];
    mk_data_w <= {mk_data_w[6:0], 1'b0};
    mk_data_i <=  mk_recv;
    mk_bit    <=  mk_bit + 1;

    // Прием очередного байта
    if (mk_bit == 7) begin

        mk_data_w <= 8'hFF;

        case (mk_state)

            // IDLE
            0: begin

                // Обнаружена команда
                if (mk_recv[7:6] == 2'b01) begin

                    mk_state <= 1;
                    mk_command <= mk_recv[5:0];

                end

            end

            // Прием команды
            // ---------------------------------------------------------
            1: begin mk_state <= 2; mk_arg[31:24] <= mk_recv; end
            2: begin mk_state <= 3; mk_arg[23:16] <= mk_recv; end
            3: begin mk_state <= 4; mk_arg[15:8 ] <= mk_recv; end
            4: begin mk_state <= 5; mk_arg[ 7:0 ] <= mk_recv; end
            5: begin mk_state <= 6; /* CRC, Выдать BSY=0 */

                mk_data_w <= 8'h00;
                case (mk_command)

                    // IDLE OK
                    0: begin mk_data_w <= 8'h01; mk_state <= 0; end

                endcase

            end

        endcase

    end

end

endmodule
