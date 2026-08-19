----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08.08.2025 16:21:16
-- Design Name: 
-- Module Name: AIOConstants - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

package IC1_Constants is

    constant SFT_RST_ADDR    : std_logic_vector(31 downto 2) := x"1000000" & "01";

	constant REG_TEST1_ADDR  : std_logic_vector(31 downto 2) := x"1000000" & "10";
	constant REG_TEST2_ADDR  : std_logic_vector(31 downto 2) := x"1000000" & "11";
	constant REG_TEST3_ADDR  : std_logic_vector(31 downto 2) := x"1000001" & "00";

    constant TAT_REG_ADDR   : std_logic_vector(31 downto 2) := x"1000010" & "00";

    constant PSIM_ASW_ADDR  : std_logic_vector(31 downto 2) := x"1000020" & "00";
    constant AM1_ASW_ADDR   : std_logic_vector(31 downto 2) := x"1000020" & "01";

    constant LOOM_ID_ADDR   : std_logic_vector(31 downto 2) := x"1000030" & "00";
    constant RIO_PWR_ADDR   : std_logic_vector(31 downto 2) := x"1000040" & "00";
    
    constant DAC_CONFIG_ADDR    : std_logic_vector(11 downto 2) := x"00" & "00";
    constant DAC_VOUT_ADDR      : std_logic_vector(11 downto 2) := x"00" & "01";
    constant DAC_AMP_ADDR       : std_logic_vector(11 downto 2) := x"00" & "10";
    constant DAC_MOD_ADDR       : std_logic_vector(11 downto 2) := x"00" & "11";
    constant DAC_CMD_ADDR       : std_logic_vector(11 downto 2) := x"01" & "00";
    constant DAC_RATE_ADDR      : std_logic_vector(11 downto 2) := x"01" & "01";
    constant DAC_STATUS_ADDR    : std_logic_vector(11 downto 2) := x"01" & "10";
    constant DAC_RST_ADDR       : std_logic_vector(11 downto 2) := x"01" & "11";

    constant DAC_MASTER_EN_ADDR   : std_logic_vector(31 downto 2) := x"1000102" & "00";
    -- Write any value to this address to issue a global phase-sync pulse.
    -- All 12 GainSine accumulators reset to 0 on the identical 50 MHz clock edge.
    constant DAC_PHASE_SYNC_ADDR  : std_logic_vector(31 downto 2) := x"1000102" & "01";
    constant DAC_CH1_ADDR       : std_logic_vector(19 downto 0) := x"10001";
    constant DAC_CH2_ADDR       : std_logic_vector(19 downto 0) := x"10002";
    constant DAC_CH3_ADDR       : std_logic_vector(19 downto 0) := x"10003";
    constant DAC_CH4_ADDR       : std_logic_vector(19 downto 0) := x"10004";
    constant DAC_CH5_ADDR       : std_logic_vector(19 downto 0) := x"10005";
    constant DAC_CH6_ADDR       : std_logic_vector(19 downto 0) := x"10006";
    constant DAC_CH7_ADDR       : std_logic_vector(19 downto 0) := x"10007";
    constant DAC_CH8_ADDR       : std_logic_vector(19 downto 0) := x"10008";
    constant DAC_CH9_ADDR       : std_logic_vector(19 downto 0) := x"10009";
    constant DAC_CH10_ADDR      : std_logic_vector(19 downto 0) := x"1000A";
    constant DAC_CH11_ADDR      : std_logic_vector(19 downto 0) := x"1000B";
    constant DAC_CH12_ADDR      : std_logic_vector(19 downto 0) := x"1000C";

    --DAC Command Constants
    constant CMD_OUTPUT_RANGE : std_logic_vector(7 downto 0) := "00011001"; -- Address 0x19
    constant CMD_REF_CONFIG   : std_logic_vector(7 downto 0) := "00010101"; -- Address 0x15
    constant CMD_STREAM_MODE  : std_logic_vector(7 downto 0) := "00001110"; -- Address 0x0E
    constant CMD_TRANS_REG    : std_logic_vector(7 downto 0) := "00001111"; -- Address 0x0F
    constant CMD_CH0_INPUT    : std_logic_vector(7 downto 0) := "00110011"; -- Address 0x33
    constant CMD_DIR_DAC_DATA : std_logic_vector(7 downto 0) := X"34";--x"2A";
    constant CMD_IF_CONF      : std_logic_vector(7 downto 0) := x"01";
    --Pulse measurement constants
    constant PULSE_SAMPLE_START_ADDR : std_logic_vector(31 downto 2) := x"1000050" & "00";
    constant PULSE_SAMPLE_STATUS_ADDR : std_logic_vector(31 downto 2) := x"1000050" & "01";
    constant PULSE_SAMPLE_OFF_ADDR : std_logic_vector(31 downto 2) := x"1000050" & "10";
    constant PULSE_SAMPLE_RST_ADDR : std_logic_vector(31 downto 2) := x"1000050" & "11";
    constant PULSE_SAMPLE_COM_ADDR : std_logic_vector(31 downto 4) := x"1000050";

    constant PULSE_HIGH_WIDTH_ADDR : std_logic_vector(1 downto 0) := "00";
    constant PULSE_LOW_WIDTH_ADDR : std_logic_vector(1 downto 0) := "11";

    constant PULSE_SAMP_CH1_ADDR : std_logic_vector(27 downto 0) := x"1000051";
    constant PULSE_SAMP_CH2_ADDR : std_logic_vector(27 downto 0) := x"1000052";
    constant PULSE_SAMP_CH3_ADDR : std_logic_vector(27 downto 0) := x"1000053";
    constant PULSE_SAMP_CH4_ADDR : std_logic_vector(27 downto 0) := x"1000054";
    constant PULSE_SAMP_CH5_ADDR : std_logic_vector(27 downto 0) := x"1000055";
    constant PULSE_SAMP_CH6_ADDR : std_logic_vector(27 downto 0) := x"1000056";
    constant PULSE_SAMP_CH7_ADDR : std_logic_vector(27 downto 0) := x"1000057";
    constant PULSE_SAMP_CH8_ADDR : std_logic_vector(27 downto 0) := x"1000058";
    constant PULSE_SAMP_CH9_ADDR : std_logic_vector(27 downto 0) := x"1000059";
    constant PULSE_SAMP_CH10_ADDR : std_logic_vector(27 downto 0) := x"100005A";
    constant PULSE_SAMP_CH11_ADDR : std_logic_vector(27 downto 0) := x"100005B";
    constant PULSE_SAMP_CH12_ADDR : std_logic_vector(27 downto 0) := x"100005C"; 
    
    -- DAC soft-reset address (any write asserts RSTN)
    constant DAC_RESET_ADDR          : std_logic_vector(31 downto 2) := x"1000070" & "01";

    -- AD3551R generic register access (see dac_if_logic for usage sequence)
    --   Byte addresses: ADDR=0x400001C8, WDATA=0x400001CC, NBYTES=0x400001D0
    --                   CMD =0x400001D4, RDATA=0x400001D8, STATUS=0x400001DC
    constant DAC_GREG_ADDR_ADDR      : std_logic_vector(31 downto 2) := x"1000070" & "10"; -- W: reg addr [6:0]
    constant DAC_GREG_WDATA_ADDR     : std_logic_vector(31 downto 2) := x"1000070" & "11"; -- W: write data [15:0]
    constant DAC_GREG_NBYTES_ADDR    : std_logic_vector(31 downto 2) := x"1000071" & "00"; -- W: [0]=0→1byte, 1→2bytes
    constant DAC_GREG_CMD_ADDR       : std_logic_vector(31 downto 2) := x"1000071" & "01"; -- W: [0]=RW, triggers start
    constant DAC_GREG_RDATA_ADDR     : std_logic_vector(31 downto 2) := x"1000071" & "10"; -- R: captured read data [15:0]
    constant DAC_GREG_STATUS_ADDR    : std_logic_vector(31 downto 2) := x"1000071" & "11"; -- R: [0]=busy
    constant DAC_VOUT_RANGE_ADDR     : std_logic_vector(31 downto 2) := x"1000072" & "00"; -- R: [0]=busy
    --ADC Constants
    constant ADC_CMD_ADDR           : std_logic_vector(31 downto 2) := x"1000060" & "00";
    constant ADC_STATUS_ADDR        : std_logic_vector(31 downto 2) := x"1000060" & "01";
    constant ADC_DATA_ADDR          : std_logic_vector(31 downto 2) := x"1000060" & "10";
    constant ADC_FIFO_STATUS_ADDR   : std_logic_vector(31 downto 2) := x"1000060" & "11";
    constant ADC_RST_ADDR           : std_logic_vector(31 downto 2) := x"1000061" & "00";
    constant ADC_TOTAL_ADDR         : std_logic_vector(31 downto 8) := x"100006";

    component SPIMaster is
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
    end component;

    component GainSine is
    Port (
            clk_50mhz      : in  STD_LOGIC;
            reset          : in  STD_LOGIC;
            user_gain      : in  std_logic_vector(15 downto 0);
            mod_index      : in  std_logic_vector(31 downto 0);
            start_gen      : in  STD_LOGIC;
            phase_sync     : in  STD_LOGIC;  -- global phase-reset pulse from main_ic1
            dac_data_out   : out STD_LOGIC_VECTOR (15 downto 0);
            new_data_ready : out STD_LOGIC;
            new_data_ack   : in  STD_LOGIC
        );
    end component;

    component DAC_CONFIG is
    port(
        rstn        : in  std_logic;
        clk_50m     : in  std_logic;
        config_en   : in  std_logic;
        start_dc    : in  std_logic;
        start_sine  : in  std_logic;
        phase_sync  : in  std_logic;           -- global phase-reset pulse
        user_gain   : in  std_logic_vector(15 downto 0);
        mod_index   : in  std_logic_vector(31 downto 0);
        spi_start    : out std_logic;
        spi_data     : out std_logic_vector(23 downto 0);
        spi_bits     : out integer range 0 to 7;
        spi_keep_csn : out std_logic;
        spi_ready    : in  std_logic;
        ldac_n      : out std_logic
    );
    end component;

    component WaveGen is
    Port (
            rstn           : in    std_logic;
            lclk           : in    std_logic;
            ladd           : in    std_logic_vector(11 downto 2);
            lwrn           : in    std_logic;
            blastn         : in    std_logic;
            csn            : in    std_logic;
            clk_50m        : in    std_logic;
            ldata          : in    std_logic_vector(31 downto 0);
            spi_sclk       : out   STD_LOGIC;
            spi_io         : inout STD_LOGIC_VECTOR(3 downto 0);
            spi_cs_n       : out   STD_LOGIC;
            ldac_n         : out   std_logic;
            dac_rstn       : out   std_logic;
            mux_sel        : out   std_logic_vector(1 downto 0);
            master_en      : in    std_logic;
            phase_sync     : in    std_logic   -- global phase-reset pulse (50 MHz domain)
    );
    end component;

    component Pulse_measure is
        port (
            clk             : in  std_logic;
            reset           : in  std_logic;
            start           : in  std_logic;
            pulse_in        : in  std_logic;
            low_width       : out std_logic_vector(31 downto 0);
            high_width      : out std_logic_vector(31 downto 0);
            overflow_low    : out std_logic;
            overflow_high   : out std_logic;
            done            : out std_logic
        );
    end component;


    component pulse_meas_bulk is

        port(
            clk_50m             : in  std_logic;
            rst_in              : in  std_logic;
            lclk                : in  std_logic;
            lwrn                : in  std_logic;
            blastn              : in  std_logic;
            addr                : in  std_logic_vector(31 downto 2);
            data_in             : in  std_logic_vector(11 downto 0);

            f_single1           : in  std_logic;
            f_single2           : in  std_logic;
            f_single3           : in  std_logic;
            f_single4           : in  std_logic;
            f_single5           : in  std_logic;

            f_diff1             : in  std_logic;
            f_diff2             : in  std_logic;
            f_diff3             : in  std_logic;
            f_diff4             : in  std_logic;
            f_diff5             : in  std_logic;
            f_diff6             : in  std_logic;
            f_diff7             : in  std_logic;
            
            com_reg_out         : out std_logic_vector(31 downto 0);

            pul_low1           : out std_logic_vector(31 downto 0);
            pul_low2           : out std_logic_vector(31 downto 0);
            pul_low3           : out std_logic_vector(31 downto 0);
            pul_low4           : out std_logic_vector(31 downto 0);
            pul_low5           : out std_logic_vector(31 downto 0);
            pul_low6           : out std_logic_vector(31 downto 0);
            pul_low7           : out std_logic_vector(31 downto 0);
            pul_low8           : out std_logic_vector(31 downto 0);
            pul_low9           : out std_logic_vector(31 downto 0);
            pul_low10          : out std_logic_vector(31 downto 0);
            pul_low11          : out std_logic_vector(31 downto 0);
            pul_low12          : out std_logic_vector(31 downto 0);

            pul_high1          : out std_logic_vector(31 downto 0);
            pul_high2          : out std_logic_vector(31 downto 0);
            pul_high3          : out std_logic_vector(31 downto 0);
            pul_high4          : out std_logic_vector(31 downto 0);
            pul_high5          : out std_logic_vector(31 downto 0);
            pul_high6          : out std_logic_vector(31 downto 0);
            pul_high7          : out std_logic_vector(31 downto 0);
            pul_high8          : out std_logic_vector(31 downto 0);
            pul_high9          : out std_logic_vector(31 downto 0);
            pul_high10         : out std_logic_vector(31 downto 0);
            pul_high11         : out std_logic_vector(31 downto 0);
            pul_high12         : out std_logic_vector(31 downto 0)
            

        );
    end component;

    component dac_if_logic is
        port(
            lclk        : in  std_logic;
            lreset      : in  std_logic;
            ladd        : in  std_logic_vector(31 downto 2);
            lwrn        : in  std_logic;
            blastn      : in  std_logic;
            ldata       : in  std_logic_vector(31 downto 0);
            dac_rdata   : out std_logic_vector(31 downto 0);   -- read-back data
            dac_busy    : out std_logic;                       -- operation in progress
            dac_sclk    : out std_logic;
            dac_io      : inout std_logic_vector(3 downto 0);  -- IO3:IO0 QSPI bus
            dac_csn     : out std_logic;
            dac_rstn    : out std_logic;
            dac_ldacn   : out std_logic;
            mux_sel     : out std_logic_vector(1 downto 0)    -- DAC output range select (for main_ic1)
        );
    end component;

    component ADC_IC is
        port(
            rst_in              : in  std_logic;
            --clk_50m             : in  std_logic;
            lclk                : in  std_logic;
            lwrn                : in  std_logic;
            blastn              : in  std_logic;
            addr                : in  std_logic_vector(31 downto 2);
            data_in             : in  std_logic_vector(31 downto 0);
            data_out            : out std_logic_vector(31 downto 0);

            -- ADC AD7671ASTZ Interface
            adc_data_in         : in  std_logic_vector(15 downto 0);
            adc_busy            : in  std_logic;
            adc_convst          : out std_logic;
            adc_csn             : out std_logic;
            adc_rdn             : out std_logic;
            adc_rstn            : out std_logic;
            adc_pdwn            : out std_logic;

            -- MUX16 ADG526AKRZ Interface (latched address)
            mux_a0              : out std_logic;
            mux_a1              : out std_logic;
            mux_a2              : out std_logic;
            mux_a3              : out std_logic;
            mux_en              : out std_logic;
            mux_rstn            : out std_logic;
            mux_wrn             : out std_logic;

            -- Final MUX ADG5404BRUZ Interface (combinational address)
            fmux_a0             : out std_logic;
            fmux_a1             : out std_logic;
            fmux_en             : out std_logic
        );
    end component;

    COMPONENT fifo_generator_512x16
    PORT (
        rst : IN STD_LOGIC;
        wr_clk : IN STD_LOGIC;
        rd_clk : IN STD_LOGIC;
        din : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        wr_en : IN STD_LOGIC;
        rd_en : IN STD_LOGIC;
        dout : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        full : OUT STD_LOGIC;
        wr_ack : OUT STD_LOGIC;
        overflow : OUT STD_LOGIC;
        empty : OUT STD_LOGIC;
        valid : OUT STD_LOGIC;
        underflow : OUT STD_LOGIC 
    );
    END COMPONENT;

   
end package IC1_Constants;