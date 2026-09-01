library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
-- DAC used is ad3551r from analog devices , required range is  +/-10V
entity dac_test is
    generic (
        SIM_MODE : boolean := false
    );
    port (
        RST_SW             : in  std_logic;
        FPGA_CLK_50MHZ     : in  std_logic;
        
        -- Test / Status outputs
        TP_CLK_TST         : out std_logic;
        STS1_LED_GREEN     : out std_logic;
        
        -- DAC interface
        --DAC_nALERT         : in  std_logic;
        DAC_nRST           : out std_logic;
        DAC_nLOAD          : out std_logic;
        DAC_nCS            : out std_logic;
        DAC_SCLK           : out std_logic;
        DAC_SDIO0          : out std_logic;
        --DAC_SDIO1          : in  std_logic;
        DAC_SDIO2          : out std_logic;
        DAC_SDIO3          : out std_logic;
        
        -- Latch interface
        --LATCH1_E           : out std_logic;
        BUS_DATA           : out std_logic_vector (15 downto 0)
    );
end dac_test;

architecture Behavioral of dac_test is

    -- Function to reduce wait time during simulation
    function get_max_wait(sim : boolean) return integer is
    begin
        if sim then return 500; else return 5000000; end if; -- 10us vs 100ms
    end function;
    constant MAX_WAIT : integer := get_max_wait(SIM_MODE);

    type main_state_t is (
        ST_RESET, 
        ST_WAIT_RDY,
        ST_LATCH_CFG,
        ST_CFG_PWR,
        ST_CFG_PWR_WAIT,
        ST_CFG_RNG,
        ST_CFG_RNG_WAIT,
        ST_CFG_DAC,
        ST_CFG_DAC_WAIT,
        ST_IDLE
    );
    signal state : main_state_t := ST_RESET;
	-- Counter for delays (sized to hold 5,000,000 for 100ms at 50MHz)
    signal delay_cnt : integer range 0 to 5000000 := 0;
    
    -- SPI Transceiver signals
    signal spi_start    : std_logic := '0';
    signal spi_active   : std_logic := '0';
    signal spi_done     : std_logic := '0';
    signal spi_data_req : std_logic_vector(23 downto 0) := (others => '0');
    signal spi_bits_req : integer range 0 to 24 := 0;
    
    signal tx_reg       : std_logic_vector(23 downto 0) := (others => '0');
    signal spi_bit_cnt  : integer range 0 to 24 := 0;
    signal spi_phase    : std_logic := '0';
    signal clk_div      : unsigned(1 downto 0) := "00";
    signal sclk_int     : std_logic := '0';

    -- Heartbeat
    signal hb_cnt       : integer range 0 to 24999999 := 0;
    signal hb_val       : std_logic := '0';

begin

    -- Tie off unused pins / static pins
    DAC_SDIO2  <= '0';
    DAC_SDIO3  <= '0';
    DAC_nLOAD  <= '0'; 
    TP_CLK_TST <= sclk_int; 
    DAC_SDIO0  <= tx_reg(23); -- SDI is always the MSB of the shift register
    DAC_SCLK   <= sclk_int;
	BUS_DATA <= x"AAAA";

    -- Main State Machine
    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then
            if RST_SW = '0' then
                state <= ST_RESET;
                spi_start <= '0';
                delay_cnt <= 0;
                DAC_nRST <= '0';
                --LATCH1_E <= '0';
             
            else
                spi_start <= '0'; -- default pulse
                
                case state is
                    when ST_RESET =>
                        DAC_nRST <= '0';
                        if delay_cnt < 5000 then -- 100ms minimum reset pulse
                            delay_cnt <= delay_cnt + 1;
                        else
                            delay_cnt <= 0;
                            DAC_nRST <= '1';
                            state <= ST_WAIT_RDY;
                        end if;
                        
                    when ST_WAIT_RDY =>
                        if delay_cnt < MAX_WAIT then
                            delay_cnt <= delay_cnt + 1;
                        else
                            delay_cnt <= 0;
                            state <= ST_LATCH_CFG;
                        end if;

                    when ST_LATCH_CFG =>
                        --BUS_DATA <= x"00AA";
                        --LATCH1_E <= '1';
                        if delay_cnt < 100 then -- short pulse for external latch
                            delay_cnt <= delay_cnt + 1;
                        else
                            delay_cnt <= 0;
                            --LATCH1_E <= '0';
                            state <= ST_CFG_PWR;
                        end if;

                    when ST_CFG_PWR =>
                        if spi_active = '0' then
                            -- Reg 0x18 <= 0x00 (Power up DAC)
                            spi_data_req <= x"180000"; 
                            spi_bits_req <= 16;
                            spi_start <= '1';
                            state <= ST_CFG_PWR_WAIT;
                        end if;

                    when ST_CFG_PWR_WAIT =>
                        if spi_done = '1' then
                            state <= ST_CFG_RNG;
                        end if;

                    when ST_CFG_RNG =>
                        if spi_active = '0' then
                            -- Reg 0x19 <= 0x04 (Span +/- 10V)
                            spi_data_req <= x"190400"; 
                            spi_bits_req <= 16;
                            spi_start <= '1';
                            state <= ST_CFG_RNG_WAIT;
                        end if;

                    when ST_CFG_RNG_WAIT =>
                        if spi_done = '1' then
                            state <= ST_CFG_DAC;
                        end if;

                    when ST_CFG_DAC =>
                        if spi_active = '0' then
                            -- Reg 0x2A <= 0xBD9C (DAC update 5V output)
                            spi_data_req <= x"2ABD9C"; 
                            spi_bits_req <= 24;
                            spi_start <= '1';
                            state <= ST_CFG_DAC_WAIT;
                        end if;

                    when ST_CFG_DAC_WAIT =>
                        if spi_done = '1' then
                            state <= ST_IDLE;
                        end if;

                    when ST_IDLE =>
                        -- Initialization done, resting state
                        null;
                end case;
            end if;
        end if;
    end process;

    -- SPI Transmitter (Mode 0: CPOL=0, CPHA=0)
    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then
            if RST_SW = '0' then
                spi_active <= '0';
                spi_done <= '0';
                DAC_nCS <= '1';
                sclk_int <= '0';
                clk_div <= "00";
            else
                spi_done <= '0'; 
                clk_div <= clk_div + 1;
                
                if spi_start = '1' then
                    spi_active <= '1';
                    DAC_nCS <= '0';
                    sclk_int <= '0';
                    spi_phase <= '0';
                    tx_reg <= spi_data_req;
                    spi_bit_cnt <= spi_bits_req;
                    clk_div <= "00"; 
                elsif spi_active = '1' then
                    -- 6.25 MHz SPI Clock Generation
                    if clk_div = "11" then 
                        if spi_phase = '0' then
                            sclk_int <= '1'; -- Rising edge: DAC captures data
                            spi_phase <= '1';
                        else
                            sclk_int <= '0'; -- Falling edge: Host shifts new bit
                            spi_phase <= '0';
                            if spi_bit_cnt = 1 then
                                spi_active <= '0';
                                DAC_nCS <= '1';
                                spi_done <= '1';
                            else
                                spi_bit_cnt <= spi_bit_cnt - 1;
                                tx_reg <= tx_reg(22 downto 0) & '0';
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- 1Hz Heartbeat LED indicator
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

end Behavioral;