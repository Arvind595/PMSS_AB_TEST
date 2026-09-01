library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity dac_test_tb is
end dac_test_tb;

architecture behavior of dac_test_tb is

    -- Component Declaration for the Unit Under Test (UUT)
    component dac_test
    generic (
        SIM_MODE : boolean := false
    );
    port(
         RST_SW             : in  std_logic;
         FPGA_CLK_50MHZ     : in  std_logic;
         TP_CLK_TST         : out std_logic;
         STS1_LED_GREEN     : out std_logic;
         --DAC_nALERT         : in  std_logic;
         DAC_nRST           : out std_logic;
         DAC_nLOAD          : out std_logic;
         DAC_nCS            : out std_logic;
         DAC_SCLK           : out std_logic;
         DAC_SDIO0          : out std_logic;
         --DAC_SDIO1          : in  std_logic;
         DAC_SDIO2          : out std_logic;
         DAC_SDIO3          : out std_logic;
         LATCH1_E           : out std_logic;
         BUS_DATA           : out std_logic_vector(15 downto 0)
        );
    end component;

    -- Inputs
    signal RST_SW             : std_logic := '0';
    signal FPGA_CLK_50MHZ     : std_logic := '0';
    --signal DAC_nALERT         : std_logic := '1';
    signal DAC_SDIO1          : std_logic := '0';

    -- Outputs
    signal TP_CLK_TST         : std_logic;
    signal STS1_LED_GREEN     : std_logic;
    signal DAC_nRST           : std_logic;
    signal DAC_nLOAD          : std_logic;
    signal DAC_nCS            : std_logic;
    signal DAC_SCLK           : std_logic;
    signal DAC_SDIO0          : std_logic;
    signal DAC_SDIO2          : std_logic;
    signal DAC_SDIO3          : std_logic;
    signal LATCH1_E           : std_logic;
    signal BUS_DATA           : std_logic_vector(15 downto 0);

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: dac_test 
        generic map (
            SIM_MODE => true
        )
        port map (
            RST_SW => RST_SW,
            FPGA_CLK_50MHZ => FPGA_CLK_50MHZ,
            TP_CLK_TST => TP_CLK_TST,
            STS1_LED_GREEN => STS1_LED_GREEN,
            --DAC_nALERT => DAC_nALERT,
            DAC_nRST => DAC_nRST,
            DAC_nLOAD => DAC_nLOAD,
            DAC_nCS => DAC_nCS,
            DAC_SCLK => DAC_SCLK,
            DAC_SDIO0 => DAC_SDIO0,
            --DAC_SDIO1 => DAC_SDIO1,
            DAC_SDIO2 => DAC_SDIO2,
            DAC_SDIO3 => DAC_SDIO3,
            LATCH1_E => LATCH1_E,
            BUS_DATA => BUS_DATA
        );

    -- Clock process definitions
    clk_process : process
    begin
        FPGA_CLK_50MHZ <= '0';
        wait for CLK_PERIOD/2;
        FPGA_CLK_50MHZ <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus process
    stim_proc: process
    begin		
        -- hold reset state for 100 ns.
        RST_SW <= '0';
        wait for 100 ns;	
        RST_SW <= '1';
        
        -- Let the simulation run out through the transactions
        wait for 500 us;
        
        -- End Simulation 
        std.env.stop;
    end process;

end behavior;