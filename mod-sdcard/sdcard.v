/** Модуль работы с SPI-интерфейсом SD-карты

Конфигурация для DE0
.spi_miso   (SD_DATA[0]),       // Входящие данные
.spi_mosi   (SD_CMD),           // Исходящие
.spi_sclk   (SD_CLK),           // Тактовая частота
.spi_cs     (SD_DATA[3]),       // Выбор чипа
*/

module sdcard(

    // 25 Mhz
    input  wire     clock,

    // SPI Физический интерфейс
    output reg      spi_cs,
    output reg      spi_sclk,
    input  wire     spi_miso,
    output reg      spi_mosi,

    // Интерфейс взаимодействия
    input  wire     command,
    output reg      busy

);

// ---------------------------------------------------------------------

// При запуске устройства оно занято инициализацией
initial busy = 1'b1;

// Состояние контроллера (=1 Инициализация)
reg  [7:0]  t = 1;
reg  [7:0]  slow_tick = 0;
reg  [7:0]  counter   = 0;

// *********************************************************************
// КОНТРОЛЛЕР ДИСКА SD
// *********************************************************************

always @(posedge clock) begin

    case (t)

        // IDLE
        // -------------------------------------------------------------
        0: begin /* IDLE */ end

        // Инициализация устройства
        // -------------------------------------------------------------
        1: begin

            busy     <= 1;
            spi_cs   <= 1;
            spi_mosi <= 1;

            // 125*000`000
            if (slow_tick == (125 - 1)) begin

                spi_sclk    <= ~spi_sclk;
                counter     <= counter + 1;
                slow_tick   <= 0;

                // 80 ticks: отключить отсылку сигналов
                if (counter == (2*80 - 1)) {t, spi_sclk} <= 0;

            end
            // Оттикивание таймера
            else slow_tick <= slow_tick + 1;

        end


    endcase

end

endmodule
