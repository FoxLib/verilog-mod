/** Модуль работы с SPI-интерфейсом SD-карты

Конфигурация для DE0
.spi_miso   (SD_DATA[0]),       // Входящие данные
.spi_mosi   (SD_CMD),           // Исходящие
.spi_sclk   (SD_CLK),           // Тактовая частота
.spi_cs     (SD_DATA[3]),       // Выбор чипа
*/

module sdcard #(parameter SKIPINIT = 0) (

    // 25 Mhz
    input  wire      clock,

    // SPI Физический интерфейс
    output reg       spi_cs,
    output reg       spi_sclk,
    input  wire      spi_miso,
    output reg       spi_mosi,

    // Интерфейс взаимодействия
    output reg       busy,
    output wire      timeout,
    output reg       error,
    output reg [7:0] errorno
);

// ОБЪЯВЛЕНИЯ
// ---------------------------------------------------------------------

// Когда наступает неактивный период
`define SPI_TIMEOUT_CNT     2500000

// При запуске устройства оно занято инициализацией
initial begin busy = 1; spi_cs = 1; spi_mosi = 1; spi_sclk = 0; error = 0; errorno = 0; end

// При timeout = 0, МК карты все еще активен, потом уходит в сон
assign timeout = (timeout_cnt == `SPI_TIMEOUT_CNT);

// СОСТОЯНИЕ ПРОЦЕССОРА
// ---------------------------------------------------------------------

// Состояние контроллера (=0 IDLE, =1 Инициализация, =4 SDCommand, =5 INIT)
reg  [3:0]  t  = 5;
reg  [2:0]  k  = 0;     // PUT|GET
reg  [2:0]  m  = 0;     // SDCommand
reg  [2:0]  i  = 0;
reg  [2:0]  n  = 0;

reg  [7:0]  data_w      = 8'h5A; // Данные на запись
reg  [7:0]  data_r      = 8'h00; // Прочитанные данные
reg  [7:0]  slow_tick   = 0;
reg  [7:0]  counter     = 0;
reg  [11:0] timeout_k   = 0;
reg  [24:0] timeout_cnt = `SPI_TIMEOUT_CNT;

reg  [3:0]  fn  = 0;    // Возврат из t=2 (PUT|GET)
reg  [3:0]  fn2 = 0;    // Возврат из t=4 (SD-Command)

// Процедура SD_Command (cmd, arg)
reg [ 7:0]  sd_cmd = 6'h00;
reg [31:0]  sd_arg = 32'h00000000;
reg [ 7:0]  status = 8'hFF; // Ответ от SD-Command

// *********************************************************************
// КОНТРОЛЛЕР ДИСКА SD
// *********************************************************************

always @(posedge clock) begin

    case (t)

        // IDLE
        0: begin

            k <= 0;
            m <= 0;
            n <= 0;
            busy <= 0;

            // Отсчет таймаута
            if (timeout_cnt < `SPI_TIMEOUT_CNT) timeout_cnt <= timeout_cnt + 1;

            // При обнаружений команды --> error <= 0

        end

        // Инициализация устройства
        1: begin

            busy     <= 1;
            spi_cs   <= 1;
            spi_mosi <= 1;

            // 125 тиков x 2 = 250; 25.000.000 / 250 = 100 kHz
            if (slow_tick == 125-1) begin

                spi_sclk    <= ~spi_sclk;
                counter     <= counter + 1;
                slow_tick   <= 0;

                // 80 ticks: отключить отсылку сигналов
                if (counter == (2*80 - 1)) begin {spi_sclk, timeout_cnt} <= 0; t <= fn; end

            end
            // Оттикивание таймера
            else slow_tick <= slow_tick + 1;

        end

        // Чтение или запись SPI
        2: begin

            t <= 3;
            k <= 0;
            spi_cs  <= 0;   // Перевод устройства в активный режим
            busy    <= 1;   // Устройство сейчас занято
            counter <= 0;   // Сброс счетчика

        end

        3: case (k)

            // CLK=0
            0: begin k <= 1; spi_sclk <= 0; end
            1: begin k <= 2; spi_mosi <= data_w[7]; data_w <= {data_w[6:0], 1'b0}; end
            // CLK=1
            2: begin k <= 3; spi_sclk <= 1; counter <= counter + 1; end
            3: begin

                k      <= 0;
                data_r <= {data_r[6:0], spi_miso};
                if (counter == 8) k <= 4;

            end

            // Вернуться к процедуре fn, CLK=0, DAT=0
            4: begin spi_sclk <= 0; spi_mosi <= 0; t <= fn; end

        endcase

        // SD Command
        4: case (m)

            // Сброс параметров
            0: begin m <= 1; timeout_k <= 4095; fn <= 4; busy <= 1; end

            // Прочитать следующий байт
            1: begin m <= 2; t <= 2; data_w <= 8'hFF; end

            // Проверить, что принят байт FFh
            2: begin

                i <= 0;
                m <= (data_r == 8'hFF) ? 3 : 1;

                if (timeout_k == 0) begin error <= 1; t <= 0; end
                timeout_k <= timeout_k - 1;

             end

            // Отсылка команды
            3: begin

                timeout_k <= 255;
                m <= i == 5 ? 4 : 3;
                t <= 2;

                case (i)

                    // Команда PUT(sd_cmd | 0x40)
                    0: data_w <= {sd_cmd[7], 1'b1, sd_cmd[5:0]};

                    // Аргумент
                    1: data_w <= sd_arg[31:24];
                    2: data_w <= sd_arg[23:16];
                    3: data_w <= sd_arg[15:8 ];
                    4: data_w <= sd_arg[ 7:0 ];

                    // CRC
                    5: data_w <=
                    /* SD_CMD0 */ sd_cmd[5:0] == 0 ? 8'h95 :
                    /* SD_CMD8 */ sd_cmd[5:0] == 8 ? 8'h87 : 8'hFF;

                endcase

                i <= i + 1;

            end

            // Ожидание ответа BSY=0
            4: begin m <= 5; t <= 2; data_w <= 8'hFF; end // GET
            5: begin

                // BSY=0 -> Перейти к 6
                if (data_r == 8'hFF) m <= 4; else t <= fn2;

                // Произошла ошибка получения статуса, выход к IDLE
                if (timeout_k == 0) begin error <= 1; t <= 0; end
                timeout_k <= timeout_k - 1;

                // Ответ команды
                status <= data_r;

            end

        endcase

        // SD INIT
        5: case (n)

            // Подача 80 тактов
            0: begin n <= 1; fn <= 5; fn2 <= 5; if (SKIPINIT == 0) t <= 1; end

            // Запрос команды IDLE
            1: begin n <= 2; t <= 4; sd_cmd <= 6'h00; sd_arg <= 0; end

            // Проверка на status=01, должен быть 01h
            2: begin errorno <= status; if (status == 8'h01) n <= 3; else begin error <= 1; t <= 0; end end

        endcase

    endcase

end

endmodule
