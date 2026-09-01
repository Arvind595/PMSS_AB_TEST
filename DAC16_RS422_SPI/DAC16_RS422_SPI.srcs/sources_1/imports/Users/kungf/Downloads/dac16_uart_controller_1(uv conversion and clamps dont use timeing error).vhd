library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rs422_pkg.all;

--------------------------------------------------------------------------------
-- dac16_uart_controller.vhd
--
-- Application layer on top of rs422_packet_controller / uart_phy / rs422_pkg
-- (used as-is, unmodified) and 16x dac_ad3551r_ch.
--
-- Command packet (8 bytes, MSB-first voltage field):
--   Byte0 = 0x55                 sync/header byte
--   Byte1 = 0x01                 command: write constant voltage
--   Byte2 = channel (0-15)
--   Byte3 = Voltage[31:24]       MSB of a signed 32-bit uV value
--   Byte4 = Voltage[23:16]
--   Byte5 = Voltage[15:8]
--   Byte6 = Voltage[7:0]         LSB
--   Byte7 = 0x00                 reserved
--
-- On a valid command (Byte0=0x55, Byte1=0x01, Byte2 in 0..15):
--   - the uV value is converted to a 16-bit AD3551R code and written to the
--     selected channel's DAC register (see uv_to_code below)
--   - the exact 8 received bytes are echoed back over UART
--
-- On an invalid command (Byte1 /= 0x01, OR Byte0 /= 0x55, OR channel > 15):
--   - no DAC write is issued
--   - the 8 bytes are echoed back with Byte1 forced to 0xFF; all other
--     bytes (including Byte0) are echoed as received
--
--   ASSUMPTION: the spec only called out "operation command not matching
--   0x01" as the error case. Bad sync byte (Byte0) and out-of-range channel
--   (Byte2 > 15) are folded into the same error path here as a safety
--   measure - flag if you want different handling (e.g. silently drop
--   instead of replying) for either of those two cases.
--
-- Voltage-to-code conversion: requests outside the nominal +/-10V
-- instrument range (+/-10,000,000 uV) are CLAMPED to +/-10V rather than
-- rejected as an error - the command is still acknowledged as valid (Byte1
-- echoed as 0x01), just saturated. Flag if out-of-range magnitude should
-- instead be treated as an error.
--
-- Register addresses (0x18/0x19/0x2A) are now VERIFIED against the AD3551R
-- datasheet (Rev. A) - see the Registers tab of dac_voltage_calculator.html.
-- The transfer function is also now datasheet-exact rather than an
-- idealized +/-10V: per Table 8 (predefined output spans), CH0_OUTPUT_RANGE
-- = 0x04 actually gives code 0x0000 = -10.382V (VZS) and code 0xFFFF =
-- +10.380V (VFS), not a symmetric +/-10.000V - Analog Devices builds in a
-- ~3% overrange margin on every predefined span on purpose. uv_to_code
-- below still clamps REQUESTS to the nominal +/-10V instrument range, but
-- converts them using the true VZS/VFS so a request for exactly +10.000V
-- lands on the correct code rather than incorrectly assuming it's 0xFFFF.
--------------------------------------------------------------------------------

entity dac16_uart_controller is
    generic (
        SIM_MODE  : boolean := false;
        CLK_FREQ  : integer := 50_000_000;
        BAUD_RATE : integer := 115200
    );
    port (
        RST_SW         : in  std_logic; -- active low
        FPGA_CLK_50MHZ : in  std_logic;

        RS422_TX       : out std_logic;
        RS422_RX       : in  std_logic;
		RS422_EN	   : out std_logic;
		RS422_nEN	   : out std_logic;

        DAC_nRST       : out std_logic_vector(15 downto 0);
        DAC_nLOAD      : out std_logic_vector(15 downto 0);
        DAC_nCS        : out std_logic_vector(15 downto 0);
        DAC_SCLK       : out std_logic_vector(15 downto 0);
        DAC_SDIO0      : out std_logic_vector(15 downto 0);
        DAC_SDIO2      : out std_logic_vector(15 downto 0);
        DAC_SDIO3      : out std_logic_vector(15 downto 0);
		
		BUS_DATA       : out std_logic_vector(15 downto 0);

        STS1_LED_GREEN : out std_logic;
		STS1_LED_YELLO : out std_logic;
        TP_CLK_TST     : out std_logic
    );
end entity dac16_uart_controller;

architecture rtl of dac16_uart_controller is

    type code_array_t is array (0 to 15) of std_logic_vector(15 downto 0);

    -- Power-on default per channel - staircase test pattern, recomputed
    -- against the corrected (datasheet-exact) transfer function below so
    -- these hex codes actually match their labeled voltages. UART commands
    -- override these at runtime regardless.
    constant CH_DAC_CODE : code_array_t := (
         0 => x"8C57",  -- CH00 = 1.000 V
         1 => x"BDA9",  -- CH01 = 5.000 V
         2 => x"9281",  -- CH02 = 1.500 V
         3 => x"C3D3",  -- CH03 = 5.500 V
         4 => x"98AC",  -- CH04 = 2.000 V
         5 => x"C9FE",  -- CH05 = 6.000 V
         6 => x"9ED6",  -- CH06 = 2.500 V
         7 => x"D028",  -- CH07 = 6.500 V
         8 => x"A500",  -- CH08 = 3.000 V
         9 => x"D652",  -- CH09 = 7.000 V
        10 => x"AB2A",  -- CH10 = 3.500 V
        11 => x"E2A7",  -- CH11 = 8.000 V
        12 => x"B155",  -- CH12 = 4.000 V
        13 => x"EEFB",  -- CH13 = 9.000 V
        14 => x"B77F",  -- CH14 = 4.500 V
        15 => x"FB50"   -- CH15 = 10.000 V
    );
    constant RANGE_CODE : std_logic_vector(7 downto 0) := x"04"; -- +/-10V, all channels

    -- Converts a signed microvolt value to a 16-bit AD3551R code using the
    -- ACTUAL zero-scale/full-scale voltages for the +/-10V predefined span
    -- (CH0_OUTPUT_RANGE = 0x04), per Table 8 of the AD3551R datasheet:
    -- code 0x0000 = -10.382V (VZS), code 0xFFFF = +10.380V (VFS) - not an
    -- idealized +/-10.000V. Requests are still clamped to the nominal
    -- +/-10V instrument range before conversion (the extra ~3% headroom is
    -- manufacturing margin, not part of the advertised span), but the
    -- conversion itself uses the true VZS/VFS so a request for exactly
    -- +10.000V lands on the correct code rather than 0xFFFF. Round-to-
    -- nearest (ties round up), matching the calculator tool.
    --
    -- Takes the raw 32-bit signed value directly (rather than a VHDL
    -- integer) and clamps in the signed domain before ever calling
    -- to_integer. VHDL's guaranteed integer range is only
    -- -(2**31 - 1) .. (2**31 - 1) - one short of the full 32-bit two's-
    -- complement range at the most-negative end - so calling to_integer on
    -- an unconstrained 32-bit signed triggers Vivado's "Integer conversion
    -- function is truncating input" warning regardless of the actual
    -- runtime value. Clamping first and only converting the resulting
    -- 25-bit-wide value avoids that entirely.
    function uv_to_code(v_uv_in : signed(31 downto 0)) return std_logic_vector is
        constant VZS_UV   : integer := -10_382_000;      -- code 0x0000 (Table 8)
        constant VFS_UV   : integer :=  10_380_000;      -- code 0xFFFF (Table 8)
        constant SPAN_UV  : integer := VFS_UV - VZS_UV;  -- 20,762,000
        constant CLAMP_HI : signed(31 downto 0) := to_signed(10_000_000, 32);
        constant CLAMP_LO : signed(31 downto 0) := to_signed(-10_000_000, 32);
        variable v_uv_clamped : signed(24 downto 0);      -- +/-10,000,000 fits comfortably in 25 bits
        variable v_uv       : integer;
        variable v_shifted  : integer;                    -- 382,000 .. 20,382,000 after clamp+shift
        variable shifted_u  : unsigned(24 downto 0);
        variable mult_full  : unsigned(40 downto 0);
        variable mult_round : unsigned(40 downto 0);
        variable divisor    : unsigned(40 downto 0);
        variable code_full  : unsigned(40 downto 0);
    begin
        if v_uv_in > CLAMP_HI then
            v_uv_clamped := to_signed(10_000_000, 25);
        elsif v_uv_in < CLAMP_LO then
            v_uv_clamped := to_signed(-10_000_000, 25);
        else
            v_uv_clamped := resize(v_uv_in, 25);          -- safe: already known to fit in +/-10,000,000
        end if;
        v_uv := to_integer(v_uv_clamped);                 -- 25-bit input, no truncation warning

        v_shifted  := v_uv - VZS_UV;
        shifted_u  := to_unsigned(v_shifted, 25);
        mult_full  := resize(shifted_u * to_unsigned(65535, 16), 41);
        divisor    := to_unsigned(SPAN_UV, 41);
        mult_round := mult_full + (divisor / 2);          -- round-to-nearest bias
        code_full  := mult_round / divisor;

        return std_logic_vector(resize(code_full, 16));
    end function;

    -- RS422 packet controller interconnect
    signal pkt_tx_start       : std_logic := '0';
    signal pkt_tx_data        : byte_array_t(0 to 7) := (others => (others => '0'));
    signal pkt_tx_busy        : std_logic;
    --signal pkt_tx_done        : std_logic;
    signal pkt_rx_data        : byte_array_t(0 to 7);
    signal pkt_rx_valid       : std_logic;
    --signal pkt_rx_timeout_err : std_logic;

    -- Per-channel DAC controller interconnect
    signal sclk_arr    : std_logic_vector(15 downto 0);
    signal ch_wr_start : std_logic_vector(15 downto 0) := (others => '0');
    signal ch_wr_code  : code_array_t := (others => (others => '0'));
    signal ch_wr_busy  : std_logic_vector(15 downto 0);
    --signal ch_wr_done  : std_logic_vector(15 downto 0);

    -- Application FSM
    type app_state_t is (ST_WAIT_RX, ST_VALIDATE, ST_ISSUE_WRITE, ST_WAIT_TX_FREE);
    signal app_state     : app_state_t := ST_WAIT_RX;
    signal rx_latched    : byte_array_t(0 to 7) := (others => (others => '0'));
    signal reply_bytes   : byte_array_t(0 to 7) := (others => (others => '0'));
    signal sel_channel   : integer range 0 to 15 := 0;
    signal cmd_valid     : boolean := false;
    signal computed_code : std_logic_vector(15 downto 0) := (others => '0');

    -- Heartbeat
    signal hb_cnt : integer range 0 to 24999999 := 0;
    signal hb_val : std_logic := '0';

begin

    TP_CLK_TST <= sclk_arr(0); -- test point mirrors channel 0's SCLK
    DAC_SCLK   <= sclk_arr;
	RS422_EN<='1'; -- permenantly set 1
	RS422_nEN<='0';-- permenantly set 0
	STS1_LED_YELLO<=pkt_tx_busy;
	BUS_DATA   <= x"AAAA";     -- permenantly set to AAAA

    ----------------------------------------------------------------------------
    -- RS422 packet layer (used unmodified)
    ----------------------------------------------------------------------------
    u_rs422 : entity work.rs422_packet_controller
        generic map (
            CLK_FREQ   => CLK_FREQ,
            BAUD_RATE  => BAUD_RATE,
            NUM_BYTES  => 8,
            TIMEOUT_MS => 5
        )
        port map (
            clk               => FPGA_CLK_50MHZ,
            rst               => RST_SW,
            rs422_tx          => RS422_TX,
            rs422_rx          => RS422_RX,
            tx_start          => pkt_tx_start,
            tx_data           => pkt_tx_data,
            tx_busy           => pkt_tx_busy,
            tx_done           => open,--pkt_tx_done,
            rx_data           => pkt_rx_data,
            rx_valid          => pkt_rx_valid,
            rx_timeout_err    => open,--pkt_rx_timeout_err,
            debug_rx_byte_cnt => open,
            debug_tx_byte_cnt => open
        );

    ----------------------------------------------------------------------------
    -- 16 independent AD3551R channel controllers
    ----------------------------------------------------------------------------
    gen_channels : for i in 0 to 15 generate
        ch_inst : entity work.dac_ad3551r_ch
            generic map (
                SIM_MODE   => SIM_MODE,
                RANGE_CODE => RANGE_CODE,
                DAC_CODE   => CH_DAC_CODE(i)
            )
            port map (
                RST_SW         => RST_SW,
                FPGA_CLK_50MHZ => FPGA_CLK_50MHZ,
                wr_start       => ch_wr_start(i),
                wr_code        => ch_wr_code(i),
                wr_busy        => ch_wr_busy(i),
                wr_done        => open,--ch_wr_done(i),
                DAC_nRST       => DAC_nRST(i),
                DAC_nLOAD      => DAC_nLOAD(i),
                DAC_nCS        => DAC_nCS(i),
                DAC_SCLK       => sclk_arr(i),
                DAC_SDIO0      => DAC_SDIO0(i),
                DAC_SDIO2      => DAC_SDIO2(i),
                DAC_SDIO3      => DAC_SDIO3(i)
            );
    end generate;

    ----------------------------------------------------------------------------
    -- Application FSM: validate command, issue DAC write, echo reply
    ----------------------------------------------------------------------------
    process(FPGA_CLK_50MHZ)
        variable byte0, byte1, byte2 : std_logic_vector(7 downto 0);
        variable raw_uv_slv          : std_logic_vector(31 downto 0);
        variable is_valid_v          : boolean;
        variable sel_v               : integer range 0 to 15;
        variable code_v              : std_logic_vector(15 downto 0);
        variable reply_v             : byte_array_t(0 to 7);
    begin
        if rising_edge(FPGA_CLK_50MHZ) then
            if RST_SW = '0' then
                app_state    <= ST_WAIT_RX;
                ch_wr_start  <= (others => '0');
                pkt_tx_start <= '0';
                rx_latched   <= (others => (others => '0'));
                reply_bytes  <= (others => (others => '0'));
                sel_channel  <= 0;
                cmd_valid    <= false;
            else
                ch_wr_start  <= (others => '0'); -- default pulse, all channels
                pkt_tx_start <= '0';             -- default pulse

                case app_state is
                    when ST_WAIT_RX =>
                        if pkt_rx_valid = '1' then
                            rx_latched <= pkt_rx_data;
                            app_state  <= ST_VALIDATE;
                        end if;

                    when ST_VALIDATE =>
                        byte0 := rx_latched(0);
                        byte1 := rx_latched(1);
                        byte2 := rx_latched(2);

                        is_valid_v := (byte0 = x"55") and (byte1 = x"01")
                                      and (unsigned(byte2) <= 15);

                        reply_v := rx_latched;
                        if not is_valid_v then
                            reply_v(1) := x"FF";
                        end if;
                        reply_bytes <= reply_v;
                        cmd_valid   <= is_valid_v;

                        if is_valid_v then
                            sel_v       := to_integer(unsigned(byte2));
                            sel_channel <= sel_v;

                            raw_uv_slv := rx_latched(3) & rx_latched(4)
                                        & rx_latched(5) & rx_latched(6);
                            code_v     := uv_to_code(signed(raw_uv_slv));
                            computed_code <= code_v;
                        end if;

                        app_state <= ST_ISSUE_WRITE;

                    when ST_ISSUE_WRITE =>
                        if cmd_valid then
                            if ch_wr_busy(sel_channel) = '0' then
                                ch_wr_start(sel_channel) <= '1';
                                ch_wr_code(sel_channel)  <= computed_code;
                                app_state <= ST_WAIT_TX_FREE;
                            end if;
                            -- else: hold here until the target channel frees up
                        else
                            app_state <= ST_WAIT_TX_FREE;
                        end if;

                    when ST_WAIT_TX_FREE =>
                        if pkt_tx_busy = '0' then
                            pkt_tx_data  <= reply_bytes;
                            pkt_tx_start <= '1';
                            app_state    <= ST_WAIT_RX;
                        end if;
                end case;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 1Hz heartbeat LED
    ----------------------------------------------------------------------------
    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then
            if hb_cnt = 24999999 then
                hb_cnt <= 0;
                hb_val <= not hb_val;
            else
                hb_cnt <= hb_cnt + 1;
            end if;
        end if;
    end process;
    STS1_LED_GREEN <= hb_val;

end architecture rtl;