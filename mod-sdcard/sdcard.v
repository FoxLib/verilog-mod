/** Модуль работы с SPI-интерфейсом SD-карты

Конфигурация для DE0
.spi_miso   (SD_DATA[0]),       // Входящие данные
.spi_mosi   (SD_CMD),           // Исходящие
.spi_sclk   (SD_CLK),           // Тактовая частота
.spi_cs     (SD_DATA[3]),       // Выбор чипа
*/

module SDCARD(

    // 25 Mhz
    input  wire       clock,

    // SPI Физический интерфейс
    output reg        spi_cs,
    output reg        spi_sclk,
    input  wire       spi_miso,
    output reg        spi_mosi,

    // Интерфейс взаимодействия
    output reg        busy,
    output wire       timeout,
    output reg        error,
    output reg  [7:0] errorno
);

// ОБЪЯВЛЕНИЯ
// ---------------------------------------------------------------------
// errorno:
// 1 - Таймаут ответа от SD Command (PRE)
// 2 - Таймаут ответа от SD Command (POST)
// 3 - SDInit не ответил IDLE=01h
// 4 - Тип карты неизвестен
// 5 - SDInit ACMD не ответил 00h
// 6 - SDInit CMD58 не вернул 00h
// ---------------------------------------------------------------------

localparam

    SDINIT  = 0,
    INIT    = 1,
    GETPUT  = 2,
    COMMAND = 4,
    IDLE    = 5,
    ERROR   = 6;

// Когда наступает неактивный период
`define SPI_TIMEOUT_CNT     2500000

// При запуске устройства оно занято инициализацией
initial begin busy = 1; spi_cs = 1; spi_mosi = 1; spi_sclk = 0; error = 0; errorno = 8'h80; ts = 0; end

// При timeout = 0, МК карты все еще активен, потом уходит в сон
assign timeout = (timeout_cnt == `SPI_TIMEOUT_CNT);

// СОСТОЯНИЕ ПРОЦЕССОРА
// ---------------------------------------------------------------------

// Состояние контроллера (=0 IDLE, =1 Инициализация, =4 SDCommand, =5 INIT)
reg  [3:0]  ts = 0;
reg  [2:0]  k  = 0;     // PUT|GET
reg  [2:0]  m  = 0;     // SDCommand
reg  [2:0]  i  = 0;
reg  [3:0]  m1 = 0;
reg  [1:0]  m2 = 0;
reg  [1:0]  sd_type = 0;  // 1-SD1, 2-SD2, 3-SDHC

reg  [7:0]  data_w      = 8'h5A; // Данные на запись
reg  [7:0]  data_r      = 8'h00; // Прочитанные данные
reg  [7:0]  slow_tick   = 0;
reg  [7:0]  counter     = 0;
reg  [11:0] timeout_k   = 0;
reg  [11:0] timeout_n   = 0;
reg  [24:0] timeout_cnt = `SPI_TIMEOUT_CNT;

reg  [3:0]  fn  = 0;    // Возврат из t=2 (PUT|GET)
reg  [3:0]  fn2 = 0;    // Возврат из t=4 (SD-Command)

// Процедура SD_Command (cmd, arg)
reg [ 5:0]  sd_cmd = 6'h00;
reg [31:0]  sd_arg = 32'h00000000;
reg [ 7:0]  status = 8'hFF; // Ответ от SD-Command

// *********************************************************************
// КОНТРОЛЛЕР ДИСКА SD
// *********************************************************************

always @(posedge clock) begin

    case (ts)

        // SD INIT
        SDINIT: case (m1)

            // Подача 80 тактов
            0: begin m1 <= 1; fn <= SDINIT; fn2 <= SDINIT; m <= 0; ts <= INIT; sd_type <= 0; busy <= 1; end

            // Запрос команды IDLE
            1: begin m1 <= 2; ts <= COMMAND; sd_cmd <= 0; sd_arg <= 0; end

            // Проверка на status=01, должен быть 01h
            2: begin

                if (status == 8'h01) m1 <= 3; /* ВАЛИДНО */
                else begin error <= 1; errorno <= 3; ts <= 5; end

            end

            // CMD8: Проверка наличия поддержки SD2
            3: begin m1 <= 4; ts <= COMMAND; sd_cmd <= 8; sd_arg <= 32'h01AA; end

            // Тест типа карты
            4: begin m1 <= 5; m2 <= 0; timeout_n <= 4095;

                // Если в бите 2 есть 1, то это устаревшая карта SD1
                if (status[2]) begin sd_type <= 1; m1 <= 7; end

            end

            // Получение 4 байт (если это SD2)
            5: begin m1 <= 6; fn <= SDINIT; ts <= GETPUT; data_w <= 8'hFF; end
            6: begin m1 <= 5; m2 <= m2 + 1;

                // Сканируем 4-й байт
                if (m2 == 3) begin

                    // Проверка наличия байта AAh
                    if (data_r == 8'hAA)
                         begin m1 <= 7; sd_type <= 2; end
                    else begin ts <= ERROR; errorno <= 4; end

                end

            end

            // ACMD(0x29, 0x40000000 : 0)
            // Инициализация карты и отправка кода поддержки SDHC если SD2
            7: begin m1 <= 8; ts <= COMMAND; sd_cmd <= 8'h37; sd_arg <= 0; end
            8: begin m1 <= 9; ts <= COMMAND; sd_cmd <= 8'h29; sd_arg <= (sd_type == 2 ? 32'h40000000 : 0); end
            9: begin m1 <= 7; // status=00h - READY

                // Если карта SD2, отослать SD_CMD58 и проверить на 00h
                if (status == 8'h00) begin

                    // Прочесть OCR
                    if (sd_type == 2) m1 <= 10;
                    // Для SD1 не нужно читать OCR
                    else begin ts <= IDLE; spi_cs <= 1; end

                end

                // Истечение таймаута
                if (timeout_n == 0) begin ts <= ERROR; errorno <= 5; end

                // Делать запросы пока не истечет таймер
                timeout_n <= timeout_n - 1;

            end

            // CMD58(0) должен вернуть 0
            10: begin m1 <= 11; m2 <= 0; ts <= COMMAND; sd_cmd <= 8'h3A; sd_arg <= 0; end
            11: begin if (status == 8'h00) m1 <= 12; else begin ts <= ERROR; errorno <= 6; end end

            // Прочитать ответ от карты (4 байта)
            12: begin m1 <= 13; fn <= SDINIT; ts <= GETPUT; data_w <= 8'hFF; end
            13: begin m1 <= 12; m2 <= m2 + 1;

                // Если первый байт ответа имеет ответ 11xxxxxx - это SDHC
                if (m2 == 0 && data_r[7:6] == 2'b11) begin sd_type <= 3; end

                // Был прочтен последний байт из OCR
                if (m2 == 3) begin ts <= IDLE; spi_cs <= 1; end

            end

        endcase

        // Инициализация устройства [INIT]
        INIT: begin

            busy     <= 1;
            spi_cs   <= 1;
            spi_mosi <= 1;

            // 125 тиков x 2 = 250; 25.000.000 / 250 = 100 kHz
            if (slow_tick == 125-1) begin

                spi_sclk  <= ~spi_sclk;
                counter   <= counter + 1;
                slow_tick <= 0;

                // 80 ticks: отключить отсылку сигналов
                if (counter == (2*80 - 1)) begin {spi_sclk, timeout_cnt} <= 0; ts <= fn; end

            end
            // Оттикивание таймера
            else slow_tick <= slow_tick + 1;

        end

        // Чтение или запись SPI [GETPUT]
        GETPUT: begin

            ts      <= 3;
            k       <= 0;
            spi_cs  <= 0;   // Перевод устройства в активный режим
            counter <= 0;   // Сброс счетчика

        end

        GETPUT+1: case (k)

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
            4: begin spi_sclk <= 0; spi_mosi <= 0; ts <= fn; end

        endcase

        // SD Command [COMMAND]
        COMMAND: case (m)

            // Сброс параметров
            0: begin m <= 1; timeout_k <= 4095; fn <= 4; end

            // Прочитать следующий байт
            1: begin m <= 2; ts <= GETPUT; data_w <= 8'hFF; end

            // Проверить, что принят байт FFh
            2: begin m <= (data_r == 8'hFF) ? 3 : 1;

                i <= 0;
                if (timeout_k == 0) begin error <= 1; errorno <= 1; ts <= IDLE; spi_cs <= 1; end
                timeout_k <= timeout_k - 1;

             end

            // Отсылка команды
            3: begin

                timeout_k <= 255;
                m  <= (i == 5) ? 4 : 3;
                ts <= GETPUT;

                case (i)

                    // Команда PUT(sd_cmd | 0x40)
                    0: data_w <= {2'b01, sd_cmd[5:0]};

                    // Аргумент
                    1: data_w <= sd_arg[31:24];
                    2: data_w <= sd_arg[23:16];
                    3: data_w <= sd_arg[15:8 ];
                    4: data_w <= sd_arg[ 7:0 ];

                    // CRC
                    5: data_w <=
                        sd_cmd[5:0] == 0 ? 8'h95 :          // CMD0
                        sd_cmd[5:0] == 8 ? 8'h87 : 8'hFF;   // CMD8, Other

                endcase

                i <= i + 1;

            end

            // Ожидание ответа BSY=0
            4: begin m <= 5; ts <= GETPUT; data_w <= 8'hFF; end // GET
            5: begin m <= 4;

                // Ответ команды
                status <= data_r;

                // BSY=0 -> Данные готовы
                if (data_r[7] == 0) begin ts <= fn2; m <= 0; end

                // Произошла ошибка получения статуса, выход к IDLE
                if (timeout_k == 0) begin error <= 1; errorno <= 2; ts <= IDLE; spi_cs <= 1; end

                // Уменьшается счетчик
                timeout_k <= timeout_k - 1;

            end

        endcase

        // IDLE
        IDLE: begin

            k   <= 0;
            m   <= 0;
            m1  <= 0;
            busy <= 0;

            // Отсчет таймаута
            if (timeout_cnt < `SPI_TIMEOUT_CNT) timeout_cnt <= timeout_cnt + 1;

            // При обнаружений команды READ | WRITE --> error <= 0, errorno <= 0

        end

        // Получена ошибка
        ERROR: begin ts <= IDLE; error <= 1; spi_cs <= 1; end

    endcase

end

endmodule
