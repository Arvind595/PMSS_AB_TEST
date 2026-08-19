----------------------------------------------------------------------------------
-- Module Name  : DAC_CONFIG - Behavioral
-- Description  : AD3551R QSPI SDR configuration and waveform output controller.
--
-- Operational flow:
--   1. On config_en pulse: run 6-step register initialisation sequence, then
--      enter ST_READY.
--   2. In ST_READY:
--        start_dc='1', start_sine='0'  -> DC mode  (one shot, waits for start_dc='0')
--        start_sine='1', start_dc='0'  -> Sine mode (continuous until start_sine='0')
--
-- Config sequence (QSPI SDR, NIBBLES_TO_TX=4 per step):
--   Step 1 : Write 0x81 -> reg 0x00  (SW_RESET_MSB | SW_RESET_LSB)
--   Step 2 : Wait 100 ms
--   Step 3 : Write 0x02 -> reg 0x0E  (STREAM_MODE LENGTH = 2)
--   Step 4 : Write 0x04 -> reg 0x0F  (STREAM_LENGTH_KEEP_VALUE, single SPI)
--   Step 5 : Write 0x01 -> reg 0x15  (REF_CONFIG)
--   Step 6 : Write 0x04 -> reg 0x19  (+-10V output range)
--
-- DC mode  : transmit CMD_DIR_DAC_DATA (0x2A) + user_gain [15:0] once.
--            Pulses ldac_n after SPI completes. Waits for start_dc='0' before
--            returning to ST_READY.
--
-- Sine mode: continuously transmit CMD_DIR_DAC_DATA (0x2A) + dac_data_out
--            from GainSine. Pulses ldac_n after each SPI frame. Exits when
--            start_sine='0'.
--
-- QSPI frame encoding (matches SPIMaster nibble engine):
--   4 nibbles : DATA_IN[23:16]=addr, DATA_IN[15:8]=data_byte, DATA_IN[7:0]=x00
--   6 nibbles : DATA_IN[23:16]=cmd,  DATA_IN[15:0]=16-bit data
--
-- Revision:
-- Revision 0.01 - File Created
-- Revision 0.02 - Rewritten for QSPI SDR SPIMaster; new config sequence;
--                 separate start_dc / start_sine inputs; removed force_csn_low
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.IC1_Constants.all;

entity DAC_CONFIG is
port(
    rstn        : in  std_logic;
    clk_50m     : in  std_logic;           -- 50 MHz clock

    -- Mode triggers (from WaveGen, already CDC'd)
    config_en   : in  std_logic;           -- pulse to start DAC init sequence
    start_dc    : in  std_logic;           -- '1' = DC output mode
    start_sine  : in  std_logic;           -- '1' = sine output mode
    phase_sync  : in  std_logic;           -- 1-cycle pulse: reset all phase accumulators to 0

    -- Waveform parameters
    user_gain   : in  std_logic_vector(15 downto 0);
    mod_index   : in  std_logic_vector(31 downto 0);

    -- QSPI SPIMaster interface
    spi_start    : out std_logic;
    spi_data     : out std_logic_vector(23 downto 0);
    spi_bits     : out integer range 0 to 7;
    spi_keep_csn : out std_logic;   -- '1' = hold CS_N low between sine frames
    spi_ready    : in  std_logic;

    ldac_n      : out std_logic
);
end DAC_CONFIG;

architecture Behavioral of DAC_CONFIG is

    ---------------------------------------------------------------------------
    -- FSM
    ---------------------------------------------------------------------------
    type fsm_t is (
        ST_CFG_IDLE,
        ST_CFG_SWRST_SEND,  ST_CFG_SWRST_WAIT,
        ST_CFG_100MS,
        ST_CFG_STREAM_SEND, ST_CFG_STREAM_WAIT,
        ST_CFG_TRANS_SEND,  ST_CFG_TRANS_WAIT,
        ST_CFG_REF_SEND,    ST_CFG_REF_WAIT,
        ST_CFG_RANGE_SEND,  ST_CFG_RANGE_WAIT,
        ST_READY,
        ST_DC_SEND,         ST_DC_SPI_WAIT,   ST_DC_LDAC,  ST_DC_DONE,
        ST_SINE_WAIT_DATA,
        ST_SINE_SEND,       ST_SINE_SPI_WAIT,
        ST_SINE_LDAC
    );
    signal state : fsm_t := ST_CFG_IDLE;

    ---------------------------------------------------------------------------
    -- 100 ms wait: 5,000,000 cycles @ 50 MHz
    ---------------------------------------------------------------------------
    constant C_100MS  : integer := 5_000_000;
    signal wait_cnt   : integer range 0 to 5_000_001 := 0;

    ---------------------------------------------------------------------------
    -- SPI drive registers
    ---------------------------------------------------------------------------
    signal spi_start_int    : std_logic := '0';
    signal spi_data_int     : std_logic_vector(23 downto 0) := (others => '0');
    signal spi_bits_int     : integer range 0 to 7 := 0;
    signal spi_keep_csn_int : std_logic := '0';
    signal ldac_n_int       : std_logic := '1';

    -- Set on entry to sine mode; cleared after the first 6-nibble (CMD+DATA)
    -- frame so subsequent frames send only 4 nibbles of data (stream mode).
    signal sine_first_frame : std_logic := '0';

    ---------------------------------------------------------------------------
    -- GainSine interface
    ---------------------------------------------------------------------------
    signal dac_data_out   : std_logic_vector(15 downto 0) := (others => '0');
    signal dac_data_latch : std_logic_vector(15 downto 0) := (others => '0');
    signal new_data_ready : std_logic := '0';
    signal new_data_ack   : std_logic := '0';

begin

    ---------------------------------------------------------------------------
    -- GainSine LUT instance
    ---------------------------------------------------------------------------
    sine_lut_tab : GainSine
        port map (
            clk_50mhz      => clk_50m,
            reset          => rstn,
            user_gain      => user_gain,
            mod_index      => mod_index,
            start_gen      => start_sine,
            phase_sync     => phase_sync,
            dac_data_out   => dac_data_out,
            new_data_ready => new_data_ready,
            new_data_ack   => new_data_ack
        );

    spi_start    <= spi_start_int;
    spi_data     <= spi_data_int;
    spi_bits     <= spi_bits_int;
    spi_keep_csn <= spi_keep_csn_int;
    ldac_n       <= ldac_n_int;

    ---------------------------------------------------------------------------
    -- Main FSM
    --
    -- SPI handshake convention (matches original DAC_CONFIG style):
    --   SEND state : spi_ready='1' -> assert spi_start, stay in SEND state.
    --               spi_ready='0' -> clear spi_start (default), move to WAIT.
    --   WAIT state : stay until spi_ready='1' (transfer complete), then advance.
    ---------------------------------------------------------------------------
    process(clk_50m)
    begin
        if rising_edge(clk_50m) then
            if rstn = '0' then
                state            <= ST_CFG_IDLE;
                spi_start_int    <= '0';
                spi_data_int     <= (others => '0');
                spi_bits_int     <= 0;
                spi_keep_csn_int <= '0';
                ldac_n_int       <= '1';
                new_data_ack     <= '0';
                sine_first_frame <= '0';
                wait_cnt         <= 0;
            elsif phase_sync = '1' and
                  (state = ST_SINE_WAIT_DATA or state = ST_SINE_SEND or
                   state = ST_SINE_SPI_WAIT  or state = ST_SINE_LDAC) then
                -- Synchronise FSM with GainSine phase reset.
                -- Force both channels to ST_SINE_WAIT_DATA on the same cycle.
                -- SPIMaster finishes its current nibble-clock naturally;
                -- CSN deasserts once spi_busy goes low (KEEP_CSN_LOW='0').
                -- Next SPI frame will re-send CMD+DATA (sine_first_frame='1')
                -- to re-enter stream mode cleanly.
                spi_start_int    <= '0';
                spi_keep_csn_int <= '0';
                sine_first_frame <= '1';
                ldac_n_int       <= '1';
                new_data_ack     <= '0';
                state            <= ST_SINE_WAIT_DATA;

            else
                -- Defaults (overridden below)
                spi_start_int <= '0';
                new_data_ack  <= '0';

                case state is

                    -----------------------------------------------------------
                    -- Wait for host to trigger DAC configuration
                    -----------------------------------------------------------
                    when ST_CFG_IDLE =>
                        ldac_n_int <= '1';
                        if config_en = '1' then
                            state <= ST_CFG_SWRST_SEND;
                        end if;

                    -----------------------------------------------------------
                    -- Step 1: Write 0x81 -> reg 0x00  (SW reset)
                    --   NIBBLES=4: DATA_IN[23:16]=0x00(addr), [15:8]=0x81(data)
                    -----------------------------------------------------------
                    when ST_CFG_SWRST_SEND =>
                        if spi_ready = '1' then
                            spi_data_int  <= x"00" & x"81" & x"00";
                            spi_bits_int  <= 4;
                            spi_start_int <= '1';
                        else
                            state <= ST_CFG_SWRST_WAIT;
                        end if;

                    when ST_CFG_SWRST_WAIT =>
                        if spi_ready = '1' then
                            wait_cnt <= 0;
                            state    <= ST_CFG_100MS;
                        end if;

                    -----------------------------------------------------------
                    -- Step 2: Wait 100 ms
                    -----------------------------------------------------------
                    when ST_CFG_100MS =>
                        if wait_cnt = C_100MS then
                            wait_cnt <= 0;
                            state    <= ST_CFG_STREAM_SEND;
                        else
                            wait_cnt <= wait_cnt + 1;
                        end if;

                    -----------------------------------------------------------
                    -- Step 3: Write 0x02 -> reg 0x0E  (STREAM_MODE LENGTH = 2)
                    -----------------------------------------------------------
                    when ST_CFG_STREAM_SEND =>
                        if spi_ready = '1' then
                            spi_data_int  <= CMD_STREAM_MODE & x"02" & x"00";
                            spi_bits_int  <= 4;
                            spi_start_int <= '1';
                        else
                            state <= ST_CFG_STREAM_WAIT;
                        end if;

                    when ST_CFG_STREAM_WAIT =>
                        if spi_ready = '1' then
                            state <= ST_CFG_TRANS_SEND;
                        end if;

                    -----------------------------------------------------------
                    -- Step 4: Write 0x04 -> reg 0x0F  (STREAM_LENGTH_KEEP_VALUE)
                    -----------------------------------------------------------
                    when ST_CFG_TRANS_SEND =>
                        if spi_ready = '1' then
                            spi_data_int  <= CMD_TRANS_REG & x"04" & x"00";
                            spi_bits_int  <= 4;
                            spi_start_int <= '1';
                        else
                            state <= ST_CFG_TRANS_WAIT;
                        end if;

                    when ST_CFG_TRANS_WAIT =>
                        if spi_ready = '1' then
                            state <= ST_CFG_REF_SEND;
                        end if;

                    -----------------------------------------------------------
                    -- Step 5: Write 0x01 -> reg 0x15  (REF_CONFIG)
                    -----------------------------------------------------------
                    when ST_CFG_REF_SEND =>
                        if spi_ready = '1' then
                            spi_data_int  <= CMD_REF_CONFIG & x"01" & x"00";
                            spi_bits_int  <= 4;
                            spi_start_int <= '1';
                        else
                            state <= ST_CFG_REF_WAIT;
                        end if;

                    when ST_CFG_REF_WAIT =>
                        if spi_ready = '1' then
                            state <= ST_CFG_RANGE_SEND;
                        end if;

                    -----------------------------------------------------------
                    -- Step 6: Write 0x04 -> reg 0x19  (+-10V output range)
                    -----------------------------------------------------------
                    when ST_CFG_RANGE_SEND =>
                        if spi_ready = '1' then
                            spi_data_int  <= CMD_OUTPUT_RANGE & x"04" & x"00";
                            spi_bits_int  <= 4;
                            spi_start_int <= '1';
                        else
                            state <= ST_CFG_RANGE_WAIT;
                        end if;

                    when ST_CFG_RANGE_WAIT =>
                        if spi_ready = '1' then
                            state <= ST_READY;
                        end if;

                    -----------------------------------------------------------
                    -- Config complete: dispatch to DC or Sine mode
                    -----------------------------------------------------------
                    when ST_READY =>
                        ldac_n_int       <= '1';
                        spi_keep_csn_int <= '0';
                        if start_dc = '1' and start_sine = '0' then
                            state <= ST_DC_SEND;
                        elsif start_sine = '1' and start_dc = '0' then
                            sine_first_frame <= '1';   -- first frame sends CMD+DATA
                            state            <= ST_SINE_WAIT_DATA;
                        end if;

                    -----------------------------------------------------------
                    -- DC mode: send user_gain once via CMD_DIR_DAC_DATA (0x2A)
                    --   NIBBLES=6: DATA_IN[23:16]=0x2A, DATA_IN[15:0]=user_gain
                    -----------------------------------------------------------
                    when ST_DC_SEND =>
                        if spi_ready = '1' then
                            spi_data_int  <= CMD_DIR_DAC_DATA & user_gain;
                            spi_bits_int  <= 6;
                            spi_start_int <= '1';
                        else
                            state <= ST_DC_SPI_WAIT;
                        end if;

                    when ST_DC_SPI_WAIT =>
                        if spi_ready = '1' then
                            ldac_n_int <= '0';        -- assert LDAC_N low
                            state      <= ST_DC_LDAC;
                        end if;

                    when ST_DC_LDAC =>
                        ldac_n_int <= '1';            -- deassert LDAC_N
                        state      <= ST_DC_DONE;

                    when ST_DC_DONE =>
                        -- Hold here until start_dc deasserts to avoid re-sending
                        if start_dc = '0' then
                            state <= ST_READY;
                        end if;

                    -----------------------------------------------------------
                    -- Sine mode: stream GainSine samples continuously
                    -----------------------------------------------------------
                    when ST_SINE_WAIT_DATA =>
                        if start_sine = '0' then
                            state <= ST_READY;
                        elsif new_data_ready = '1' then
                            -- Latch sample and ack GainSine in one cycle
                            dac_data_latch <= dac_data_out;
                            new_data_ack   <= '1';
                            state          <= ST_SINE_SEND;
                        end if;

                    -- First frame: CMD_DIR_DAC_DATA (0x2A) + 16-bit sample = 6 nibbles.
                    -- Subsequent frames (stream mode, CSN held low): data only = 4 nibbles.
                    --   DATA_IN[23:8] = sample, DATA_IN[7:0] = x"00" (not transmitted).
                    when ST_SINE_SEND =>
                        spi_keep_csn_int <= '1';   -- hold CSN low for entire sine burst
                        if spi_ready = '1' then
                            if sine_first_frame = '1' then
                                spi_data_int     <= CMD_DIR_DAC_DATA & dac_data_latch;
                                spi_bits_int     <= 6;
                                sine_first_frame <= '0';
                            else
                                -- Stream mode: address already latched by DAC; send data only.
                                spi_data_int  <= dac_data_latch & x"00";
                                spi_bits_int  <= 4;
                            end if;
                            spi_start_int <= '1';
                        else
                            state <= ST_SINE_SPI_WAIT;
                        end if;

                    when ST_SINE_SPI_WAIT =>
                        if spi_ready = '1' then
                            ldac_n_int <= '0';        -- assert LDAC_N low
                            state      <= ST_SINE_LDAC;
                        end if;

                    when ST_SINE_LDAC =>
                        ldac_n_int <= '1';            -- deassert LDAC_N
                        if start_sine = '0' then
                            spi_keep_csn_int <= '0';  -- release CS_N on exit
                            state            <= ST_READY;
                        elsif new_data_ready = '1' then
                            -- Data already ready (prepared during SPI tx); latch
                            -- here and skip ST_SINE_WAIT_DATA to save 1 cycle (20 ns).
                            dac_data_latch <= dac_data_out;
                            new_data_ack   <= '1';
                            state          <= ST_SINE_SEND;
                        else
                            state <= ST_SINE_WAIT_DATA;
                        end if;

                    when others =>
                        state <= ST_CFG_IDLE;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
