----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 04.03.2026 20:12:33
-- Design Name:
-- Module Name: SPIMaster - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description: QSPI SDR SPI master (CPOL=0, CPHA=0, MSB first).
--              4 bits transferred per SCLK cycle on IO3:IO0 simultaneously.
--              SCLK = CLK_50M / 2 = 25 MHz.
--
--              Interface:
--                START_TX     - pulse high for 1 cycle to begin a QSPI frame
--                DATA_IN      - up to 24-bit TX payload, MSB-aligned
--                NIBBLES_TO_TX- number of 4-bit nibbles to transfer (1..6)
--                IS_READ      - '0'=write (FPGA drives IO), '1'=read (FPGA tristates)
--                DATA_OUT     - captured RX data after READY returns high
--                READY        - '1' when idle / transfer complete
--
--              Engine behaviour (matches spi_engine in dac_if_logic.vhd):
--                Start     : CS_N asserted low; MSB nibble of DATA_IN
--                            pre-driven on IO3:IO0 before first rising SCLK (CPHA=0).
--                Rising    : DAC samples IO3:IO0 (write) or FPGA samples IO3:IO0 (read).
--                Falling   : Next nibble driven (write); nibble counter decremented.
--                            When counter reaches 0 on a falling edge -> end of transfer,
--                            CS_N deasserted, IO tristated, READY pulsed high.
--
-- Revision:
-- Revision 0.01 - File Created
-- Revision 0.02 - Converted to QSPI SDR nibble-serial engine
-- Additional Comments:
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity SPIMaster is
    Port (
            CLK_50M       : in    STD_LOGIC;  -- 50 MHz system clock
            RST_N         : in    STD_LOGIC;  -- Active-low reset

            -- Controller Interface
            START_TX      : in    STD_LOGIC;  -- Pulse high 1 cycle to begin frame
            DATA_IN       : in    STD_LOGIC_VECTOR(23 downto 0); -- TX data, MSB first
            NIBBLES_TO_TX : in    integer range 0 to 7;          -- Number of 4-bit nibbles (1..6)
            IS_READ       : in    STD_LOGIC;  -- '0'=FPGA drives IO, '1'=FPGA tristates (read)
            KEEP_CSN_LOW  : in    STD_LOGIC;  -- '1' = hold CS_N low between frames (stream mode)
            DATA_OUT      : out   STD_LOGIC_VECTOR(23 downto 0); -- Captured RX data
            READY         : out   STD_LOGIC;  -- '1' when idle

            -- Physical QSPI Bus
            SCLK          : out   STD_LOGIC;
            IO            : inout STD_LOGIC_VECTOR(3 downto 0);  -- IO3:IO0 bidirectional
            CS_N          : out   STD_LOGIC
        );
end SPIMaster;

architecture Behavioral of SPIMaster is

    ---------------------------------------------------------------------------
    -- QSPI nibble-serial engine signals
    ---------------------------------------------------------------------------
    signal qspi_tx_reg    : std_logic_vector(23 downto 0) := (others => '0'); -- TX shift reg
    signal qspi_nibble_cnt: integer range 0 to 7          := 0;               -- remaining nibbles
    signal spi_rx_shift   : std_logic_vector(23 downto 0) := (others => '0'); -- RX capture
    signal spi_clk_ph     : std_logic := '0';  -- '0' = rising half, '1' = falling half
    signal spi_busy       : std_logic := '0';
    signal is_read_r      : std_logic := '0';  -- latched at start

    -- IO bus drive
    signal io_out : std_logic_vector(3 downto 0) := (others => '0');
    signal io_oe  : std_logic_vector(3 downto 0) := (others => '0'); -- '1' = FPGA drives

    -- Physical line registers
    signal sclk_int : std_logic := '0';
    signal csn_int  : std_logic := '1';

begin

    ---------------------------------------------------------------------------
    -- QSPI tristate buffers
    --   io_oe = "1111" -> FPGA drives all 4 IO lines (write / command phase)
    --   io_oe = "0000" -> all tristated; peripheral drives IO3:IO0 (read phase)
    ---------------------------------------------------------------------------
    IO(0) <= io_out(0) when io_oe(0) = '1' else 'Z';
    IO(1) <= io_out(1) when io_oe(1) = '1' else 'Z';
    IO(2) <= io_out(2) when io_oe(2) = '1' else 'Z';
    IO(3) <= io_out(3) when io_oe(3) = '1' else 'Z';

    SCLK     <= sclk_int;
    CS_N     <= csn_int;
    DATA_OUT <= spi_rx_shift;

    ---------------------------------------------------------------------------
    -- QSPI SDR engine (CPOL=0, CPHA=0)
    --
    -- Write (IS_READ='0'):
    --   io_oe = "1111"; MSB nibble of DATA_IN pre-driven before first rising SCLK.
    --   Each falling SCLK drives the next nibble from qspi_tx_reg.
    --   Nibble order: DATA_IN[23:20], [19:16], [15:12], [11:8], [7:4], [3:0].
    --
    -- Read (IS_READ='1'):
    --   io_oe = "0000"; peripheral drives IO3:IO0.
    --   Each rising SCLK captures 4 bits into spi_rx_shift (shift-left, MSB first).
    --   Result after transfer complete:
    --     spi_rx_shift[23:0] with received data in the top N*4 bits.
    --
    -- SCLK = CLK_50M / 2 = 25 MHz.
    ---------------------------------------------------------------------------
    process(CLK_50M)
    begin
        if rising_edge(CLK_50M) then
            if RST_N = '0' then
                spi_busy        <= '0';
                sclk_int        <= '0';
                spi_clk_ph      <= '0';
                qspi_nibble_cnt <= 0;
                qspi_tx_reg     <= (others => '0');
                spi_rx_shift    <= (others => '0');
                io_out          <= (others => '0');
                io_oe           <= (others => '0');
                csn_int         <= '1';
                is_read_r       <= '0';
                READY           <= '1';

            else
                -- Idle: release CS_N whenever KEEP_CSN_LOW deasserts
                if spi_busy = '0' and KEEP_CSN_LOW = '0' then
                    csn_int <= '1';
                end if;

                if START_TX = '1' and spi_busy = '0' then
                    -- ---- Load and start ----------------------------------------
                    sclk_int        <= '0';
                    spi_clk_ph      <= '0';
                    spi_busy        <= '1';
                    csn_int         <= '0';
                    READY           <= '0';
                    spi_rx_shift    <= (others => '0');
                    qspi_tx_reg     <= DATA_IN;
                    qspi_nibble_cnt <= NIBBLES_TO_TX - 1;
                    is_read_r       <= IS_READ;

                    if IS_READ = '0' then
                        -- Write: pre-drive MSB nibble (CPHA=0 requirement)
                        io_out <= DATA_IN(23 downto 20);
                        io_oe  <= "1111";
                    else
                        -- Read: tristate; peripheral drives after CS_N falls
                        io_out <= (others => '0');
                        io_oe  <= "0000";
                    end if;

                elsif spi_busy = '1' then
                    spi_clk_ph <= not spi_clk_ph;

                    if spi_clk_ph = '0' then
                        -- ---- Rising SCLK ------------------------------------------
                        sclk_int <= '1';
                        -- Capture nibble from peripheral during read phase
                        if is_read_r = '1' then
                            spi_rx_shift <= spi_rx_shift(19 downto 0) & IO(3 downto 0);
                        end if;

                    else
                        -- ---- Falling SCLK -----------------------------------------
                        sclk_int <= '0';

                        if qspi_nibble_cnt = 0 then
                            -- Last nibble done: end transfer
                            spi_busy <= '0';
                            -- In stream mode (KEEP_CSN_LOW='1') hold CS_N low so the
                            -- DAC stays addressed; deassert only when released by controller.
                            if KEEP_CSN_LOW = '0' then
                                csn_int <= '1';
                            end if;
                            io_oe    <= "0000";
                            io_out   <= (others => '0');
                            READY    <= '1';
                        else
                            -- Advance TX shift register to next nibble
                            if is_read_r = '0' then
                                -- Drive next nibble MSB-first from shift register
                                io_out      <= qspi_tx_reg(19 downto 16);
                                qspi_tx_reg <= qspi_tx_reg(19 downto 0) & "0000";
                            end if;
                            qspi_nibble_cnt <= qspi_nibble_cnt - 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
