// 8N1 - без бита четности
module uart(

    input wire       reset_n,   // =0 Сброс схемы
    input wire       clock25,   // Тактовая частота 25 mhz

    // Прием
    input            rx,        // Входящие данные
    output reg       rx_ready,  // Строб готовности
    output reg [7:0] rx_byte,   // Принятые данные

    // Отсылка
    output reg       tx,        // Исходящие данные
    input      [7:0] tx_byte,   // Байт для отсылки
    input            tx_send,   // Отсылка на позитивном фронте
    output reg       tx_ready   // Данные отосланы
);

// Частота 460800 бод, 25000000 / 460800 = 54

   parameter bit_parity = 0; // Проверка четности (=1)

   parameter size = 217;    // 115200
// parameter size = 434;    // 57600
// parameter size = 2604;   // 9600

// Прием
reg [7:0] cnt   = 0;
reg [3:0] num   = 0;
reg       rdy   = 0;
reg       rtx   = 0;
reg [1:0] latrx = 0;

// Передача
reg [1:0] lattx  = 0;
reg [7:0] cnt_tx = 0;
reg [3:0] num_tx = 0;
reg       parity = 0;
reg [7:0] tbyte;

initial rx_ready = 0;
initial rx_byte  = 0;
initial tx_ready = 0;
initial tx       = 0; // 1

// Модуль приема байта
always @(posedge clock25) begin

    rx_ready <= 0;

    if (rdy) begin

        cnt <= cnt + 1;

        // Прием сигнала на середине
        if (cnt == size/2) begin

            // 11/10 бит = start(1) + data(8) + [parity(1)] + stop(1)
            if (num == 9 + bit_parity)
            // Прием данных окончен
            begin rdy <= 0; rx_ready <= 1; end
            // Сдвиг LSB
            else if (num < 9) rx_byte <= {rx, rx_byte[7:1]};

            num <= num + 1;

        end
        else if (cnt == size-1) cnt <= 0;

    end
    // Ожидание старт-бита
    else if (latrx == 2'b10) begin rdy <= 1; {cnt, num, rx_byte} <= 0; end

    // Для того, чтобы определить старт-бит
    latrx <= {latrx[0], rx};

end

// Модуль передачи
always @(posedge clock25) begin

if (reset_n == 0) begin tx <= 1; end
else begin

    tx_ready <= 1'b0;

    // Запущен процесс передачи
    if (rtx) begin

        cnt_tx <= cnt_tx + 1;

        // Установка бита в начале
        if (cnt_tx == 0) begin

            num_tx <= num_tx + 1;

            case (num_tx)

                0:  tx <= 0;      // Стартовый бит
                /* 1..8 DATA-биты */
                9:  tx <= parity; // Бит четности
                10: tx <= 1;      // Стоповый бит
                11: begin rtx <= 0; tx_ready <= 1; end // Завершить передачу
                default: begin    // Задвигается новый бит (LSB)

                    tx     <= tbyte[0];
                    tbyte  <= tbyte[7:1];
                    parity <= parity ^ tbyte[0];

                    // С битом или без бита четности
                    if (num_tx == 8 + bit_parity) num_tx <= 10;

                end

            endcase

        end
        else if (cnt_tx == size-1) cnt_tx <= 0;

    end
    // Запуск процесса передачи
    else if (lattx == 2'b01) begin

        rtx <= 1;
        {cnt_tx, num_tx, parity} <= 0;
        tbyte <= tx_byte;

    end

    // Зарегистрировать позитивный фронт SEND
    lattx <= {lattx[0], tx_send};

end

end

endmodule
