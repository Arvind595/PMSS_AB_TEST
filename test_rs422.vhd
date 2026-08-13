library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

architecture Behavioral of ab_check is

    -- ============================================================
    -- CONSTANTS
    -- ============================================================
    constant CLK_FREQ       : integer := 50000000;       -- 50 MHz
    constant BAUD_RATE      : integer := 115200;

    -- 50 MHz / 115200 = 434.0278
    constant BAUD_TICKS     : integer := CLK_FREQ / BAUD_RATE; -- 434
    constant HALF_BAUD      : integer := BAUD_TICKS / 2;       -- 217

    -- Send test byte every 100 ms
    constant TX_PERIOD      : integer := CLK_FREQ / 10;        -- 100 ms

    -- 1 Hz heartbeat
    constant HEART_TICKS    : integer := CLK_FREQ / 2;

    -- Test data
    constant TEST_BYTE      : std_logic_vector(7 downto 0) := x"55";

    -- ============================================================
    -- HEARTBEAT
    -- ============================================================
    signal heart_cnt        : integer range 0 to HEART_TICKS-1 := 0;
    signal led_green_reg    : std_logic := '0';

    -- ============================================================
    -- BAUD GENERATOR
    -- ============================================================
    signal baud_cnt         : integer range 0 to BAUD_TICKS-1 := 0;
    signal baud_tick        : std_logic := '0';

    -- ============================================================
    -- TX PERIOD TIMER
    -- ============================================================
    signal tx_period_cnt    : integer range 0 to TX_PERIOD-1 := 0;
    signal tx_start         : std_logic := '0';

    -- ============================================================
    -- UART TX
    --
    -- Frame:
    --       IDLE  START  D0 D1 D2 D3 D4 D5 D6 D7  STOP
    --         1     0     LSB ----------------> MSB   1
    -- ============================================================
    signal tx_busy          : std_logic := '0';
    signal tx_reg           : std_logic := '1';
    signal tx_data          : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_bit_cnt       : integer range 0 to 9 := 0;

    -- ============================================================
    -- UART RX
    -- ============================================================
    signal rx_sync1         : std_logic := '1';
    signal rx_sync2         : std_logic := '1';

    signal rx_busy          : std_logic := '0';
    signal rx_data          : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_bit_cnt       : integer range 0 to 7 := 0;
    signal rx_sample_cnt    : integer range 0 to BAUD_TICKS-1 := 0;

    signal rx_valid         : std_logic := '0';
    signal rx_error         : std_logic := '0';

    -- ============================================================
    -- TEST STATUS
    -- ============================================================
    signal test_ok          : std_logic := '0';

begin

    -- ============================================================
    -- OUTPUT ASSIGNMENTS
    -- ============================================================

    STS1_LED_GREEN <= led_green_reg;

    RS422_TX       <= tx_reg;

    -- Transmitter enable
    RS422_TX_EN    <= tx_busy;

    -- Complementary enable
    RS422_TX_nEN   <= not tx_busy;

    -- Baud tick test point
    TP_CLK_TST     <= baud_tick;


    -- ============================================================
    -- 1. HEARTBEAT + BAUD GENERATOR
    -- ============================================================

    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then

            -- ----------------------------------------------------
            -- 1 Hz heartbeat
            -- ----------------------------------------------------
            if heart_cnt = HEART_TICKS - 1 then
                heart_cnt     <= 0;
                led_green_reg <= not led_green_reg;
            else
                heart_cnt <= heart_cnt + 1;
            end if;


            -- ----------------------------------------------------
            -- Baud generator
            -- 115200 baud
            -- ----------------------------------------------------
            if baud_cnt = BAUD_TICKS - 1 then
                baud_cnt  <= 0;
                baud_tick <= '1';
            else
                baud_cnt  <= baud_cnt + 1;
                baud_tick <= '0';
            end if;

        end if;
    end process;


    -- ============================================================
    -- 2. GENERATE TX START EVERY 100 ms
    -- ============================================================

    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then

            tx_start <= '0';

            if tx_period_cnt = TX_PERIOD - 1 then

                tx_period_cnt <= 0;

                -- Start only if previous transmission is finished
                if tx_busy = '0' then
                    tx_start <= '1';
                end if;

            else
                tx_period_cnt <= tx_period_cnt + 1;
            end if;

        end if;
    end process;


    -- ============================================================
    -- 3. UART TRANSMITTER
    -- ============================================================

    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then

            if tx_start = '1' then

                -- Load test byte
                tx_data <= TEST_BYTE;

                -- Start transmission
                tx_busy <= '1';

                -- Start bit
                tx_reg <= '0';

                -- Bit 0 = START BIT
                tx_bit_cnt <= 0;

            elsif baud_tick = '1' and tx_busy = '1' then

                case tx_bit_cnt is

                    -- ------------------------------------------------
                    -- START BIT already transmitted
                    -- ------------------------------------------------
                    when 0 =>
                        tx_reg    <= tx_data(0);
                        tx_bit_cnt <= 1;

                    -- ------------------------------------------------
                    -- DATA BIT 1
                    -- ------------------------------------------------
                    when 1 =>
                        tx_reg     <= tx_data(1);
                        tx_bit_cnt <= 2;

                    -- ------------------------------------------------
                    -- DATA BIT 2
                    -- ------------------------------------------------
                    when 2 =>
                        tx_reg     <= tx_data(2);
                        tx_bit_cnt <= 3;

                    -- ------------------------------------------------
                    -- DATA BIT 3
                    -- ------------------------------------------------
                    when 3 =>
                        tx_reg     <= tx_data(3);
                        tx_bit_cnt <= 4;

                    -- ------------------------------------------------
                    -- DATA BIT 4
                    -- ------------------------------------------------
                    when 4 =>
                        tx_reg     <= tx_data(4);
                        tx_bit_cnt <= 5;

                    -- ------------------------------------------------
                    -- DATA BIT 5
                    -- ------------------------------------------------
                    when 5 =>
                        tx_reg     <= tx_data(5);
                        tx_bit_cnt <= 6;

                    -- ------------------------------------------------
                    -- DATA BIT 6
                    -- ------------------------------------------------
                    when 6 =>
                        tx_reg     <= tx_data(6);
                        tx_bit_cnt <= 7;

                    -- ------------------------------------------------
                    -- DATA BIT 7
                    -- ------------------------------------------------
                    when 7 =>
                        tx_reg     <= tx_data(7);
                        tx_bit_cnt <= 8;

                    -- ------------------------------------------------
                    -- STOP BIT
                    -- ------------------------------------------------
                    when 8 =>
                        tx_reg     <= '1';
                        tx_bit_cnt <= 9;

                    -- ------------------------------------------------
                    -- Transmission finished
                    -- ------------------------------------------------
                    when 9 =>
                        tx_reg     <= '1';
                        tx_busy    <= '0';
                        tx_bit_cnt <= 0;

                    when others =>
                        tx_reg  <= '1';
                        tx_busy <= '0';

                end case;

            end if;

        end if;
    end process;


    -- ============================================================
    -- 4. SYNCHRONIZE RS422_RX INTO FPGA CLOCK DOMAIN
    -- ============================================================

    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then

            rx_sync1 <= RS422_RX;
            rx_sync2 <= rx_sync1;

        end if;
    end process;


    -- ============================================================
    -- 5. UART RECEIVER
    --
    -- Detect falling edge = START BIT
    -- Then sample each data bit approximately at its center.
    -- ============================================================

    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then

            rx_valid <= '0';

            -- --------------------------------------------------------
            -- IDLE STATE
            -- --------------------------------------------------------
            if rx_busy = '0' then

                -- Detect start bit
                if rx_sync2 = '0' then

                    rx_busy       <= '1';

                    -- Wait half a baud period to sample center
                    rx_sample_cnt <= HALF_BAUD;

                    rx_bit_cnt    <= 0;

                end if;

            -- --------------------------------------------------------
            -- RECEIVING
            -- --------------------------------------------------------
            else

                if rx_sample_cnt = BAUD_TICKS - 1 then

                    rx_sample_cnt <= 0;

                    -- ----------------------------------------------
                    -- Data bits
                    -- ----------------------------------------------
                    if rx_bit_cnt <= 7 then

                        rx_data(rx_bit_cnt) <= rx_sync2;

                        if rx_bit_cnt = 7 then
                            rx_bit_cnt <= 8;
                        else
                            rx_bit_cnt <= rx_bit_cnt + 1;
                        end if;

                    -- ----------------------------------------------
                    -- Stop bit
                    -- ----------------------------------------------
                    elsif rx_bit_cnt = 8 then

                        -- Stop bit must be HIGH
                        if rx_sync2 = '1' then
                            rx_valid <= '1';
                        else
                            rx_error <= '1';
                        end if;

                        rx_busy    <= '0';
                        rx_bit_cnt <= 0;

                    end if;

                else

                    rx_sample_cnt <= rx_sample_cnt + 1;

                end if;

            end if;

        end if;
    end process;


    -- ============================================================
    -- 6. CHECK RECEIVED DATA
    -- ============================================================

    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then

            if rx_valid = '1' then

                if rx_data = TEST_BYTE then
                    test_ok <= '1';
                else
                    test_ok <= '0';
                    rx_error <= '1';
                end if;

            end if;

        end if;
    end process;


end Behavioral;