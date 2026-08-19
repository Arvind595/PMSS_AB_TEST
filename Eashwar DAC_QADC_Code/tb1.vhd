----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09.03.2026 19:18:22
-- Design Name: 
-- Module Name: tb1 - Behavioral
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
use IEEE.STD_LOGIC_TEXTIO.ALL;
  -- bring constants into scope for address values
    use work.IC1_Constants.all;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
library UNISIM;
use UNISIM.VComponents.all;

Library xpm;
use xpm.vcomponents.all;

entity tb1 is
--  Port ( );
end tb1;

architecture Behavioral of tb1 is

  

    -- signals for main_ic1 ports
    signal lhold       : std_logic := '0';
    signal lreset      : std_logic := '0';
    signal lclk        : std_logic := '0'; --33MHz
    signal ladd        : std_logic_vector(31 downto 2) := (others => '0');        
    signal lwrn        : std_logic := '0';
    signal blastn      : std_logic := '1';

    signal ldata       : std_logic_vector(31 downto 0) := (others => 'Z');

    signal lholdack    : std_logic;
    signal readyn      : std_logic;

    signal TAT_RLY_DRV : std_logic_vector(26 downto 1);

    signal MUX_SIN_DI_SEL : std_logic_vector(4 downto 1);
    signal AM_SW_CTRL  : std_logic;
    signal DCM_SW_CTRL : std_logic_vector(2 downto 1);

    signal LOOM_ID     : std_logic_vector(2 downto 0) := (others => '0');

    signal RIO_P15V_EN : std_logic;
    signal RIO_N15V_EN : std_logic;
    signal RIO_P12V_EN : std_logic;
    signal RIO_N12V_EN : std_logic;

    signal sts_led     : std_logic;

    signal clk_50m     : std_logic := '0'; --50MHz

    -- SPI Master Interfaces
    signal dac1_rstn   : std_logic;
    signal dac1_load   : std_logic;
    signal dac1_csn    : std_logic;
    signal dac1_sclk   : std_logic;
    --signal dac1_mosi   : std_logic;
    --signal dac1_miso   : std_logic := '0';
    signal dac1_io     : std_logic_vector(3 downto 0);  -- IO3:IO0 QSPI bus
    signal dac1_alertn : std_logic := '0';
    signal dac1_ctrl1_a0 : std_logic;
    signal dac1_ctrl1_a1 : std_logic;

    signal dac2_rstn   : std_logic;
    signal dac2_load   : std_logic;
    signal dac2_csn    : std_logic;
    signal dac2_sclk   : std_logic;
    signal dac2_io     : std_logic_vector(3 downto 0);
    signal dac2_alertn : std_logic := '0';
    signal dac2_ctrl2_a0 : std_logic;
    signal dac2_ctrl2_a1 : std_logic;

    signal dac3_rstn   : std_logic;
    signal dac3_load   : std_logic;
    signal dac3_csn    : std_logic;
    signal dac3_sclk   : std_logic;
    signal dac3_io     : std_logic_vector(3 downto 0);
    signal dac3_alertn : std_logic := '0';
    signal dac3_ctrl3_a0 : std_logic;
    signal dac3_ctrl3_a1 : std_logic;

    signal dac4_rstn   : std_logic;
    signal dac4_load   : std_logic;
    signal dac4_csn    : std_logic;
    signal dac4_sclk   : std_logic;
    signal dac4_io     : std_logic_vector(3 downto 0);
    signal dac4_alertn : std_logic := '0';
    signal dac4_ctrl4_a0 : std_logic;
    signal dac4_ctrl4_a1 : std_logic;

    signal dac5_rstn   : std_logic;
    signal dac5_load   : std_logic;
    signal dac5_csn    : std_logic;
    signal dac5_sclk   : std_logic;
    signal dac5_io     : std_logic_vector(3 downto 0);
    signal dac5_alertn : std_logic := '0';
    signal dac5_ctrl5_a0 : std_logic;
    signal dac5_ctrl5_a1 : std_logic;

    signal dac6_rstn   : std_logic;
    signal dac6_load   : std_logic;
    signal dac6_csn    : std_logic;
    signal dac6_sclk   : std_logic;
    signal dac6_io     : std_logic_vector(3 downto 0);
    signal dac6_alertn : std_logic := '0';
    signal dac6_ctrl6_a0 : std_logic;
    signal dac6_ctrl6_a1 : std_logic;

    signal dac7_rstn   : std_logic;
    signal dac7_load   : std_logic;
    signal dac7_csn    : std_logic;
    signal dac7_sclk   : std_logic;
    signal dac7_io     : std_logic_vector(3 downto 0);
    signal dac7_alertn : std_logic := '0';
    signal dac7_ctrl7_a0 : std_logic;
    signal dac7_ctrl7_a1 : std_logic;

    signal dac8_rstn   : std_logic;
    signal dac8_load   : std_logic;
    signal dac8_csn    : std_logic;
    signal dac8_sclk   : std_logic;
    signal dac8_io     : std_logic_vector(3 downto 0);
    signal dac8_alertn : std_logic := '0';
    signal dac8_ctrl8_a0 : std_logic;
    signal dac8_ctrl8_a1 : std_logic;

    signal dac9_rstn   : std_logic;
    signal dac9_load   : std_logic;
    signal dac9_csn    : std_logic;
    signal dac9_sclk   : std_logic;
    signal dac9_io     : std_logic_vector(3 downto 0);
    signal dac9_alertn : std_logic := '0';
    signal dac9_ctrl9_a0 : std_logic;
    signal dac9_ctrl9_a1 : std_logic;

    signal dac10_rstn   : std_logic;
    signal dac10_load   : std_logic;
    signal dac10_csn    : std_logic;
    signal dac10_sclk   : std_logic;
    signal dac10_io     : std_logic_vector(3 downto 0);
    signal dac10_alertn : std_logic := '0';
    signal dac10_ctrl10_a0 : std_logic;
    signal dac10_ctrl10_a1 : std_logic;

    signal dac11_rstn   : std_logic;
    signal dac11_load   : std_logic;
    signal dac11_csn    : std_logic;
    signal dac11_sclk   : std_logic;
    signal dac11_io     : std_logic_vector(3 downto 0);
    signal dac11_alertn : std_logic := '0';
    signal dac11_ctrl11_a0 : std_logic;
    signal dac11_ctrl11_a1 : std_logic;

    signal dac12_rstn   : std_logic;
    signal dac12_load   : std_logic;
    signal dac12_csn    : std_logic;
    signal dac12_sclk   : std_logic;
    signal dac12_io     : std_logic_vector(3 downto 0);
    signal dac12_alertn : std_logic := '0';
    signal dac12_ctrl12_a0 : std_logic;
    signal dac12_ctrl12_a1 : std_logic;

    signal f_single1   : std_logic := '0';
    signal f_single2   : std_logic := '0';
    signal f_single3   : std_logic := '0';
    signal f_single4   : std_logic := '0';
    signal f_single5   : std_logic := '0';

    signal f_diff1     : std_logic := '0';
    signal f_diff2     : std_logic := '0';
    signal f_diff3     : std_logic := '0';
    signal f_diff4     : std_logic := '0';
    signal f_diff5     : std_logic := '0';
    signal f_diff6     : std_logic := '0';
    signal f_diff7     : std_logic := '0';

     -- ADC AD7671ASTZ Interface
    signal  adc_data_in         : std_logic_vector(15 downto 0) := x"AAAA";
    signal  adc_busy            : std_logic := '0';
    signal  adc_convst          : std_logic;
    signal  adc_csn             : std_logic;
    signal  adc_rdn             : std_logic;
    signal  adc_rstn            : std_logic;
    signal  adc_pdwn            : std_logic;

        -- MUX16 ADG526AKRZ Interface (latched address)
    signal    mux_a0              : std_logic;
    signal    mux_a1              : std_logic;
    signal    mux_a2              : std_logic;
    signal    mux_a3              : std_logic;
    signal    mux_en              : std_logic;
    signal    mux_rstn            : std_logic;
    signal    mux_wrn             : std_logic;

        -- Final MUX ADG5404BRUZ Interface (combinational address)
    signal    fmux_a0             : std_logic;
    signal    fmux_a1             : std_logic;
    signal    fmux_en             : std_logic;


    component main_ic1 is
        port(
            lhold       : in std_logic;
            lreset      : in std_logic;
            lclk        : in std_logic; --33MHZ
            ladd       : in std_logic_vector(31 downto 2);        
            lwrn        : in std_logic;
            blastn      : in std_logic;

            ldata        : inout std_logic_vector(31 downto 0);

            lholdack    : out std_logic;
            readyn      : out std_logic;

            TAT_RLY_DRV : out std_logic_vector(26 downto 1);

            MUX_SIN_DI_SEL : out std_logic_vector(4 downto 1);
            AM_SW_CTRL : out std_logic;
            DCM_SW_CTRL : out std_logic_vector(2 downto 1);

            LOOM_ID     : in std_logic_vector(2 downto 0);

            RIO_P15V_EN : out std_logic;
            RIO_N15V_EN : out std_logic;
            RIO_P12V_EN   : out std_logic;
            RIO_N12V_EN  : out std_logic;

            sts_led     : out std_logic;

            clk_50m     : in std_logic; --50MHz

             -- SPI Master Interfaces
            dac1_rstn   : out std_logic;
            dac1_load   : out std_logic;
            dac1_csn    : out std_logic;
            dac1_sclk   : out std_logic;
            --dac1_mosi   : out std_logic;
            --dac1_miso   : in std_logic;
            dac1_io     : inout std_logic_vector(3 downto 0);
            dac1_alertn : in std_logic;
            dac1_ctrl1_a0 : out std_logic;
            dac1_ctrl1_a1 : out std_logic;

            dac2_rstn   : out std_logic;
            dac2_load   : out std_logic;
            dac2_csn    : out std_logic;
            dac2_sclk   : out std_logic;
            dac2_io     : inout std_logic_vector(3 downto 0);
            dac2_alertn : in std_logic;
            dac2_ctrl2_a0 : out std_logic;
            dac2_ctrl2_a1 : out std_logic;

            dac3_rstn   : out std_logic;
            dac3_load   : out std_logic;
            dac3_csn    : out std_logic;
            dac3_sclk   : out std_logic;
            dac3_io     : inout std_logic_vector(3 downto 0);
            dac3_alertn : in std_logic;
            dac3_ctrl3_a0 : out std_logic;
            dac3_ctrl3_a1 : out std_logic;

            dac4_rstn   : out std_logic;
            dac4_load   : out std_logic;
            dac4_csn    : out std_logic;
            dac4_sclk   : out std_logic;
            dac4_io     : inout std_logic_vector(3 downto 0);
            dac4_alertn : in std_logic;
            dac4_ctrl4_a0 : out std_logic;
            dac4_ctrl4_a1 : out std_logic;

            dac5_rstn   : out std_logic;
            dac5_load   : out std_logic;
            dac5_csn    : out std_logic;
            dac5_sclk   : out std_logic;
            dac5_io     : inout std_logic_vector(3 downto 0);
            dac5_alertn : in std_logic;
            dac5_ctrl5_a0 : out std_logic;
            dac5_ctrl5_a1 : out std_logic;

            dac6_rstn   : out std_logic;
            dac6_load   : out std_logic;
            dac6_csn    : out std_logic;
            dac6_sclk   : out std_logic;
            dac6_io     : inout std_logic_vector(3 downto 0);
            dac6_alertn : in std_logic;
            dac6_ctrl6_a0 : out std_logic;
            dac6_ctrl6_a1 : out std_logic;

            dac7_rstn   : out std_logic;
            dac7_load   : out std_logic;
            dac7_csn    : out std_logic;
            dac7_sclk   : out std_logic;
            dac7_io     : inout std_logic_vector(3 downto 0);
            dac7_alertn : in std_logic;
            dac7_ctrl7_a0 : out std_logic;
            dac7_ctrl7_a1 : out std_logic;

            dac8_rstn   : out std_logic;
            dac8_load   : out std_logic;
            dac8_csn    : out std_logic;
            dac8_sclk   : out std_logic;
            dac8_io     : inout std_logic_vector(3 downto 0);
            dac8_alertn : in std_logic;
            dac8_ctrl8_a0 : out std_logic;
            dac8_ctrl8_a1 : out std_logic;

            dac9_rstn   : out std_logic;
            dac9_load   : out std_logic;
            dac9_csn    : out std_logic;
            dac9_sclk   : out std_logic;
            dac9_io     : inout std_logic_vector(3 downto 0);
            dac9_alertn : in std_logic;
            dac9_ctrl9_a0 : out std_logic;
            dac9_ctrl9_a1 : out std_logic;

            dac10_rstn   : out std_logic;
            dac10_load   : out std_logic;
            dac10_csn    : out std_logic;
            dac10_sclk   : out std_logic;
            dac10_io     : inout std_logic_vector(3 downto 0);
            dac10_alertn : in std_logic;
            dac10_ctrl10_a0 : out std_logic;
            dac10_ctrl10_a1 : out std_logic;

            dac11_rstn   : out std_logic;
            dac11_load   : out std_logic;
            dac11_csn    : out std_logic;
            dac11_sclk   : out std_logic;
            dac11_io     : inout std_logic_vector(3 downto 0);
            dac11_alertn : in std_logic;
            dac11_ctrl11_a0 : out std_logic;
            dac11_ctrl11_a1 : out std_logic;

            dac12_rstn   : out std_logic;
            dac12_load   : out std_logic;
            dac12_csn    : out std_logic;
            dac12_sclk   : out std_logic;
            dac12_io     : inout std_logic_vector(3 downto 0);
            dac12_alertn : in std_logic;
            dac12_ctrl12_a0 : out std_logic;
            dac12_ctrl12_a1 : out std_logic;

            f_single1   : in std_logic;
            f_single2   : in std_logic;
            f_single3   : in std_logic;
            f_single4   : in std_logic;
            f_single5   : in std_logic;

            f_diff1     : in std_logic;
            f_diff2     : in std_logic;
            f_diff3     : in std_logic;
            f_diff4     : in std_logic;
            f_diff5     : in std_logic;
            f_diff6     : in std_logic;
            f_diff7     : in std_logic;
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

    constant lclk_period : time := 30.3030 ns; -- corresponds to 33MHz
    constant clk_50m_period : time := 20.0 ns; -- corresponds to 50MHz

    -- put this declaration in the declarative region of your testbench
    procedure pci_target_write_cmode (
        signal LCLK    : in  std_logic;                    -- 33 MHz
        signal LHOLD   : in  std_logic;                    -- initiator asserts
        signal LHOLDA  : out std_logic;  
        signal BLAST_n : out std_logic;
        signal LWR_n   : out std_logic;
        signal LA      : out std_logic_vector(31 downto 2);
        signal LD      : inout std_logic_vector(31 downto 0);
        signal READY_n : in  std_logic;                    -- target input
        constant ADDR  : std_logic_vector(31 downto 2);   -- word‑aligned address
        constant DATA  : std_logic_vector(31 downto 0)    -- data to write
    ) is
    begin
        -- idle bus
        BLAST_n <= '1';
        LWR_n   <= '1';
        LA      <= (others => 'Z');
        LD      <= (others => 'Z');
        LHOLDA  <= '0';

        -- wait for a rising edge to start the cycle
        wait until rising_edge(LCLK);            -- cycle 1

        -- optional hold handshake
        if LHOLD = '1' then
            LHOLDA <= '1';                      -- indicate we see the hold
            wait until LHOLD = '0';
            LHOLDA <= '0';
        end if;

        -- begin bus cycle
        --BLAST_n <= '0';                         -- asserted shortly after cycle 1

        wait until rising_edge(LCLK);            -- cycle 2: address phase
        --ADS_n   <= '0';
        LA      <= ADDR;

        wait until rising_edge(LCLK);            -- cycle 3: transition to data
        --ADS_n   <= '1';                         -- address phase complete
        BLAST_n <= '0';                         -- asserted shortly after cycle 1
        LD      <= DATA;
        LWR_n   <= '1';                         -- drive write
        -- keep BLAST_n low if you plan a burst; this example is single‑beat

        -- wait for target to assert READY# (may happen any time)
        wait until READY_n = '0';

        -- end the transaction on the next rising edge
        wait until rising_edge(LCLK);            -- cycle 4 (or later if held)
        LWR_n   <= '1';
        BLAST_n <= '1';
        LD      <= (others => 'Z');
        LA      <= (others => 'Z');
        -- ADS_n already de‑asserted

        -- LHOLDA already released earlier
    end procedure;
	
    procedure pci_target_read_cmode (
        signal LCLK    : in  std_logic;                    -- 33 MHz
        signal LHOLD   : in  std_logic;                    -- initiator asserts
        signal LHOLDA  : out std_logic;
        signal BLAST_n : out std_logic;
        signal LWR_n   : out std_logic;
        signal LA      : out std_logic_vector(31 downto 2);
        signal READY_n : in  std_logic;                    -- target input
        constant ADDR  : std_logic_vector(31 downto 2)   -- word‑aligned address
    ) is
    begin
        -- idle bus
        BLAST_n <= '1';
        LWR_n   <= '1'; 
        LA      <= (others => 'Z');
        LHOLDA  <= '0';

        -- wait for a rising edge to start the cycle
        wait until rising_edge(LCLK);            -- cycle 1

        -- optional hold handshake
        if LHOLD = '1' then
            LHOLDA <= '1';                      -- indicate we see the hold
            wait until LHOLD = '0';
            LHOLDA <= '0';
        end if;



        wait until rising_edge(LCLK);
        LA      <= ADDR;
        LWR_n   <= '0';                         -- hold high for read

        wait until rising_edge(LCLK);                       -- address phase complete
                -- begin bus cycle
        BLAST_n <= '0';                         -- asserted shortly after cycle 1
       
        -- do NOT drive LD - target drives it
        -- keep BLAST_n low if you plan a burst

        -- wait for target to assert READY# (may happen any time)
        wait until READY_n = '0';

        -- capture the data on the bus
        --DATA := LD;
        wait for lclk_period * 3; -- small delay to allow data to stabilize before sampling
        -- end the transaction on the next rising edge
        wait until rising_edge(LCLK);            -- cycle 4 (or later if held)
        BLAST_n <= '1';
        LA      <= (others => 'Z');
        -- LWR_n and ADS_n already de‑asserted

        wait until rising_edge(LCLK);            -- cycle 4 (or later if held)
        LWR_n   <= '1';                         -- hold high for read

    end procedure;

    constant pulse_freq1 : time := 76.92308 us; -- corresponds to 13MHz
    constant pulse_freq2 : time := 2.5 ms; -- corresponds to
    begin


    -- instantiate the design under test
    uut: main_ic1
        port map(
            lhold => lhold,
            lreset => lreset,
            lclk => lclk,
            ladd => ladd,
            lwrn => lwrn,
            blastn => blastn,
            ldata => ldata,
            lholdack => lholdack,
            readyn => readyn,
            TAT_RLY_DRV => TAT_RLY_DRV,
            MUX_SIN_DI_SEL => MUX_SIN_DI_SEL,
            AM_SW_CTRL => AM_SW_CTRL,
            DCM_SW_CTRL => DCM_SW_CTRL,
            LOOM_ID => LOOM_ID,
            RIO_P15V_EN => RIO_P15V_EN,
            RIO_N15V_EN => RIO_N15V_EN,
            RIO_P12V_EN => RIO_P12V_EN,
            RIO_N12V_EN => RIO_N12V_EN,
            sts_led => sts_led,
            clk_50m => clk_50m,
            dac1_rstn => dac1_rstn,
            dac1_load => dac1_load,
            dac1_csn => dac1_csn,
            dac1_sclk => dac1_sclk,
            --dac1_mosi => dac1_mosi,
            --dac1_miso => dac1_miso,
            dac1_io => dac1_io,
            dac1_alertn => dac1_alertn,
            dac1_ctrl1_a0 => dac1_ctrl1_a0,
            dac1_ctrl1_a1 => dac1_ctrl1_a1,
            dac2_rstn => dac2_rstn,
            dac2_load => dac2_load,
            dac2_csn => dac2_csn,
            dac2_sclk => dac2_sclk,
            dac2_io => dac2_io,
            dac2_alertn => dac2_alertn,
            dac2_ctrl2_a0 => dac2_ctrl2_a0,
            dac2_ctrl2_a1 => dac2_ctrl2_a1,
            dac3_rstn => dac3_rstn,
            dac3_load => dac3_load,
            dac3_csn => dac3_csn,
            dac3_sclk => dac3_sclk,
            dac3_io => dac3_io,
            dac3_alertn => dac3_alertn,
            dac3_ctrl3_a0 => dac3_ctrl3_a0,
            dac3_ctrl3_a1 => dac3_ctrl3_a1,
            dac4_rstn => dac4_rstn,
            dac4_load => dac4_load,
            dac4_csn => dac4_csn,
            dac4_sclk => dac4_sclk,
            dac4_io => dac4_io,
            dac4_alertn => dac4_alertn,
            dac4_ctrl4_a0 => dac4_ctrl4_a0,
            dac4_ctrl4_a1 => dac4_ctrl4_a1,
            dac5_rstn => dac5_rstn,
            dac5_load => dac5_load,
            dac5_csn => dac5_csn,
            dac5_sclk => dac5_sclk,
            dac5_io => dac5_io,
            dac5_alertn => dac5_alertn,
            dac5_ctrl5_a0 => dac5_ctrl5_a0,
            dac5_ctrl5_a1 => dac5_ctrl5_a1,
            dac6_rstn => dac6_rstn,
            dac6_load => dac6_load,
            dac6_csn => dac6_csn,
            dac6_sclk => dac6_sclk,
            dac6_io => dac6_io,
            dac6_alertn => dac6_alertn,
            dac6_ctrl6_a0 => dac6_ctrl6_a0,
            dac6_ctrl6_a1 => dac6_ctrl6_a1,
            dac7_rstn => dac7_rstn,
            dac7_load => dac7_load,
            dac7_csn => dac7_csn,
            dac7_sclk => dac7_sclk,
            dac7_io => dac7_io,
            dac7_alertn => dac7_alertn,
            dac7_ctrl7_a0 => dac7_ctrl7_a0,
            dac7_ctrl7_a1 => dac7_ctrl7_a1,
            dac8_rstn => dac8_rstn,
            dac8_load => dac8_load,
            dac8_csn => dac8_csn,
            dac8_sclk => dac8_sclk,
            dac8_io => dac8_io,
            dac8_alertn => dac8_alertn,
            dac8_ctrl8_a0 => dac8_ctrl8_a0,
            dac8_ctrl8_a1 => dac8_ctrl8_a1,
            dac9_rstn => dac9_rstn,
            dac9_load => dac9_load,
            dac9_csn => dac9_csn,
            dac9_sclk => dac9_sclk,
            dac9_io => dac9_io,
            dac9_alertn => dac9_alertn,
            dac9_ctrl9_a0 => dac9_ctrl9_a0,
            dac9_ctrl9_a1 => dac9_ctrl9_a1,
            dac10_rstn => dac10_rstn,
            dac10_load => dac10_load,
            dac10_csn => dac10_csn,
            dac10_sclk => dac10_sclk,
            dac10_io => dac10_io,
            dac10_alertn => dac10_alertn,
            dac10_ctrl10_a0 => dac10_ctrl10_a0,
            dac10_ctrl10_a1 => dac10_ctrl10_a1,
            dac11_rstn => dac11_rstn,
            dac11_load => dac11_load,
            dac11_csn => dac11_csn,
            dac11_sclk => dac11_sclk,
            dac11_io => dac11_io,
            dac11_alertn => dac11_alertn,
            dac11_ctrl11_a0 => dac11_ctrl11_a0,
            dac11_ctrl11_a1 => dac11_ctrl11_a1,
            dac12_rstn => dac12_rstn,
            dac12_load => dac12_load,
            dac12_csn => dac12_csn,
            dac12_sclk => dac12_sclk,
            dac12_io => dac12_io,
            dac12_alertn => dac12_alertn,
            dac12_ctrl12_a0 => dac12_ctrl12_a0,
            dac12_ctrl12_a1 => dac12_ctrl12_a1,
            f_single1 => f_single1,
            f_single2 => f_single2,
            f_single3 => f_single3,
            f_single4 => f_single4,
            f_single5 => f_single5,
            f_diff1 => f_diff1,
            f_diff2 => f_diff2,
            f_diff3 => f_diff3,
            f_diff4 => f_diff4,
            f_diff5 => f_diff5,
            f_diff6 => f_diff6,
            f_diff7 => f_diff7,
            adc_data_in => adc_data_in,
            adc_busy => adc_busy,
            adc_convst => adc_convst,
            adc_csn => adc_csn,
            adc_rdn => adc_rdn,
            adc_rstn => adc_rstn,
            adc_pdwn => adc_pdwn,
            mux_a0 => mux_a0,
            mux_a1 => mux_a1,
            mux_a2 => mux_a2,
            mux_a3 => mux_a3,
            mux_en => mux_en,
            mux_rstn => mux_rstn,
            mux_wrn => mux_wrn,
            fmux_a0 => fmux_a0,
            fmux_a1 => fmux_a1,
            fmux_en => fmux_en
        );


    pulse1_process : process
    begin
        f_single1 <= '0';
        wait for pulse_freq1/2;
        f_single1 <= '1';
        wait for pulse_freq1/2;
    end process;

    pulse2_process : process
    begin
        f_single2 <= '0';
        wait for pulse_freq2/2;
        f_single2 <= '1';
        wait for pulse_freq2/2;
    end process;

    -- generate the 33MHz local clock
    lclk_process : process
    begin
        lclk <= '0';
        wait for lclk_period/2;
        lclk <= '1';
        wait for lclk_period/2;
    end process;

    -- generate 50MHz clock used by SPI etc.
    clk50_process : process
    begin
        clk_50m <= '0';
        wait for clk_50m_period/2;
        clk_50m <= '1';
        wait for clk_50m_period/2;
    end process;

    -- simple stimulus sequence
    stim_proc : process
    begin
        -- apply reset
        lreset <= '0';
        wait for 200 ns;
        lreset <= '1';
        wait for 50 ns;
        wait for 400 ns;

        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, ADC_RST_ADDR, DATA => x"00000000");
        -- wait for 100 ns;
        -- adc_busy <= '0';
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, ADC_CMD_ADDR, DATA => x"00000055");
        -- wait for 1.4 us; -- wait for DAC to process command
        -- adc_busy <= '1';
        -- wait for 1 us; -- wait for DAC to process command
        -- adc_busy <= '0';
        -- wait for 2 us;
        -- pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, ADC_STATUS_ADDR);
        -- wait for 100 ns;
        -- pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, ADC_DATA_ADDR);
        -- wait for 400 ns;
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, REG_TEST1_ADDR, DATA => x"DEADBEEF");
        -- wait for 100 ns;
        -- pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, REG_TEST1_ADDR);
        -- wait for 100 ns;
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_VOUT_ADDR), DATA => x"00000004");
        -- wait for 100 ns;
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_CONFIG_ADDR), DATA => x"00000000");
         
        -- wait for 4500 ns;

        --  pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_AMP_ADDR), DATA => x"00007FFF");
        -- wait for 100 ns;
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_MOD_ADDR), DATA => x"00553261");
        -- wait for 100 ns;

        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_CMD_ADDR), DATA => x"00000055");

        -- --pulse width measurement test
        --  pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (PULSE_SAMPLE_START_ADDR), DATA => x"00000003");

        -- wait for 6 ms;

        -- pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, PULSE_SAMPLE_STATUS_ADDR);
        -- wait for 100 ns;
        -- pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, PULSE_SAMPLE_OFF_ADDR);
        -- wait for 100 ns;
        --  pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, (PULSE_SAMP_CH1_ADDR & PULSE_HIGH_WIDTH_ADDR));
        -- wait for 100 ns;
        --  pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, (PULSE_SAMP_CH1_ADDR & PULSE_LOW_WIDTH_ADDR));
        -- wait for 100 ns;
        -- pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, (PULSE_SAMP_CH2_ADDR & PULSE_HIGH_WIDTH_ADDR));
        -- wait for 100 ns;
        --  pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, (PULSE_SAMP_CH2_ADDR & PULSE_LOW_WIDTH_ADDR));
        -- wait for 100 ns;    

        --pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_DIRECT_WRITE_ADDR, DATA => x"00005555");
        --wait for 12.2 us;
        --pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_DIRECT_WRITE_ADDR, DATA => x"0000AAAA");

        --pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_RESET_ADDR, DATA => x"00000000");
        --report "Read back ldata = " & to_hstring(ldata);
        --report "End of simulation" severity note;

        --pci_target_read_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, readyn, (DAC_GREG_STATUS_ADDR));

        --wait for 10 us;
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_GREG_ADDR_ADDR, DATA => x"00000001");
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_GREG_WDATA_ADDR, DATA => x"00000088");
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_GREG_NBYTES_ADDR, DATA => x"00000000");
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_GREG_CMD_ADDR, DATA => x"00000000");

        --wait for 2 us;
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_GREG_ADDR_ADDR, DATA => x"0000002A");
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_GREG_WDATA_ADDR, DATA => x"00005555");
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_GREG_NBYTES_ADDR, DATA => x"00000001");
        -- pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, DAC_GREG_CMD_ADDR, DATA => x"00000000");

        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_VOUT_ADDR), DATA => x"00000004");
        
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_AMP_ADDR), DATA => x"00005555");
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_CMD_ADDR), DATA => x"00000056");
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_CONFIG_ADDR), DATA => x"00000001");

        wait for 102 ms;
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_CMD_ADDR), DATA => x"00000000");
        wait for 100 us;
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_AMP_ADDR), DATA => x"00007FFF");
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_MOD_ADDR), DATA => x"00553261");
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_CH1_ADDR & DAC_CMD_ADDR), DATA => x"00000055");
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_MASTER_EN_ADDR), DATA => x"00000001");
        wait for 10 us;
        pci_target_write_cmode (lclk, lhold, lholdack, blastn, lwrn, ladd, ldata, readyn, (DAC_PHASE_SYNC_ADDR), DATA => x"00000000");

        wait;
    end process;

end Behavioral;
