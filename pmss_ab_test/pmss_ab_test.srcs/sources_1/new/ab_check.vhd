----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 13.08.2026 13:10:59
-- Design Name: 
-- Module Name: ab_check - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity ab_check is
	Port ( 
		
	   RST_SW : in STD_LOGIC;								--On Board Reset Switch Active low
	   FPGA_CLK_50MHZ : in STD_LOGIC;						--50MHZ Clock input
	   TP_CLK_TST : out STD_LOGIC;							--Test Pin output to check baud rate generation
	   --BRD_ID : in STD_LOGIC_VECTOR (3 downto 0);			--board ID DIP switches present on the board (optional)
	   --BUS_DATA : out STD_LOGIC_VECTOR (15 downto 0);		--common bus shared to two latches input data, to set the ADG1404 mux selection which sets the feedback resistors of DAC external amplifier (AD8065)
	   STS1_LED_GREEN : out STD_LOGIC;						-- Status led to indicate 1Hz system heartbeat
	   STS2_LED_YELLOW : out STD_LOGIC;						-- status led to indicate and Error/fault in RS422 Communication
	   RS422_RX : in STD_LOGIC;								
	   RS422_TX : out STD_LOGIC;
	   RS422_TX_EN : out STD_LOGIC;							--make high to Enable RS422 Transmission
	   RS422_TX_nEN : out STD_LOGIC						--make low to Enable RS422 Transmission
	   --LATCH1_nE : out STD_LOGIC;							--make High to Latch data into Latch1
	   --LATCH2_nE : out STD_LOGIC;							--make High to Latch data into Latch2
	   --nRST_EXT : in STD_LOGIC;
	   --DAC_nALERT : in STD_LOGIC_VECTOR (15 downto 0);		--Alert Pin. Active low logic output. This pin is driven low if an alert condition is detected and it is not masked by the corresponding bit in the mask register. This pin has an internal configurable pull-up resistor.
	   --DAC_nRST : out STD_LOGIC_VECTOR (15 downto 0);		--Asynchronous Reset Input. Active low logic input. When RESET is low, all registers are reset to their default values and the activity on the digital interface is ignored. The AD3551R incorporates a power-on reset (POR) circuit.	
	   --DAC_nLOAD : out STD_LOGIC_VECTOR (15 downto 0);
	   --DAC_nCS : out STD_LOGIC_VECTOR (15 downto 0);		--Load DAC, Active Low Logic Input. LDAC can be operated in synchronous mode or asynchronous mode. Pulsing this pin low causes the DAC register to be updated if the input register has new data. If this pin is tied permanently low, the DAC is automatically updated when new data is written to the input register
	   --DAC_SCLK : out STD_LOGIC_VECTOR (15 downto 0);		--Serial Clock Input
	   --DAC_SDIO0 : inout STD_LOGIC_VECTOR (15 downto 0);	--Serial Data Input in Classic SPI Mode, Serial Bidirectional Input/Output Bit 0 in Dual or Quad SPI Modes
	   --DAC_SDIO1 : inout STD_LOGIC_VECTOR (15 downto 0);	--Serial Data Output in Classic SPI Mode, Serial Bidirectional Input/Output Bit 1 in Dual or Quad SPI Modes
	   --DAC_SDIO2 : inout STD_LOGIC_VECTOR (15 downto 0);	--Serial Bidirectional Input/Output Bit 2 in Quad SPI Mode
	   --DAC_SDIO3 : inout STD_LOGIC_VECTOR (15 downto 0);	--Serial Bidirectional Input/Output Bit 3 in Quad SPI Mode
	   --DAC_MODE_QSPI : out STD_LOGIC_VECTOR (15 downto 0) -- A high level enables quad SPI interface mode
	   ); 
end ab_check;

architecture Behavioral of ab_check is

    --------------------------------------------------------------------------
    -- CONSTANTS (50 MHz Clock)
    --------------------------------------------------------------------------
    constant CLK_FREQ    : integer := 50000000;
    constant BAUD_RATE   : integer := 115200;
    constant BAUD_TICKS  : integer := CLK_FREQ / BAUD_RATE; -- 434 ticks
    constant HALF_BAUD   : integer := BAUD_TICKS / 2;       -- 217 ticks
    constant HEART_TICKS : integer := CLK_FREQ / 2;         -- 1 Hz toggle (0.5s)
    constant TX_PERIOD   : integer := CLK_FREQ / 10;        -- 100 ms period
    constant TEST_BYTE   : std_logic_vector(7 downto 0) := x"55"; 

    --------------------------------------------------------------------------
    -- SIGNALS
    --------------------------------------------------------------------------
    signal heart_cnt     : integer range 0 to HEART_TICKS - 1 := 0;
    signal led_green_reg : std_logic := '0';

    signal baud_cnt      : integer range 0 to BAUD_TICKS - 1 := 0;
    signal baud_tick     : std_logic := '0';

    signal tx_period_cnt : integer range 0 to TX_PERIOD - 1 := 0;
    signal tx_start      : std_logic := '0';
    signal tx_busy       : std_logic := '0';
    signal tx_reg        : std_logic := '1';
    signal tx_data       : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_bit_cnt    : integer range 0 to 9 := 0;

    signal rx_sync1      : std_logic := '1';
    signal rx_sync2      : std_logic := '1';

    type rx_state_type is (RX_IDLE, RX_START, RX_DATA, RX_STOP);
    signal rx_state      : rx_state_type := RX_IDLE;

    -- FIX FOR WARNING [Synth 8-13336]: Changed "default_state" to "reset_state"
    attribute fsm_safe_state : string;
    attribute fsm_safe_state of rx_state : signal is "reset_state";

    signal rx_byte       : std_logic_vector(7 downto 0) := (others => '0');
    
    -- FIX FOR WARNING [Synth 8-6014]: Retain rx_byte register during synthesis optimization
    attribute dont_touch : string;
    attribute dont_touch of rx_byte : signal is "true";

    signal rx_shift      : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_bit_cnt    : integer range 0 to 7 := 0;
    signal rx_sample_cnt : integer range 0 to BAUD_TICKS - 1 := 0;

    signal test_ok       : std_logic := '0';
    signal rx_error      : std_logic := '0';

begin

    --------------------------------------------------------------------------
    -- CONCURRENT ASSIGNMENTS
    --------------------------------------------------------------------------
    STS1_LED_GREEN  <= led_green_reg;
    STS2_LED_YELLOW <= test_ok and (not rx_error);

    RS422_TX        <= tx_reg;
    
    -- FIX FOR NOTICE [Synth 8-3917]: Enable transmitter dynamically during TX
    RS422_TX_EN     <= tx_busy;
    RS422_TX_nEN    <= not tx_busy;

    TP_CLK_TST      <= baud_tick;

    --------------------------------------------------------------------------
    -- 1. HEARTBEAT & BAUD GENERATOR
    --------------------------------------------------------------------------
    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then
            if RST_SW = '0' then
                heart_cnt     <= 0;
                led_green_reg <= '0';
                baud_cnt      <= 0;
                baud_tick     <= '0';
            else
                if heart_cnt = HEART_TICKS - 1 then
                    heart_cnt     <= 0;
                    led_green_reg <= not led_green_reg;
                else
                    heart_cnt     <= heart_cnt + 1;
                end if;

                if baud_cnt = BAUD_TICKS - 1 then
                    baud_cnt  <= 0;
                    baud_tick <= '1';
                else
                    baud_cnt  <= baud_cnt + 1;
                    baud_tick <= '0';
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 2. TRANSMIT PERIOD TIMER (100 ms)
    --------------------------------------------------------------------------
    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then
            if RST_SW = '0' then
                tx_period_cnt <= 0;
                tx_start      <= '0';
            else
                tx_start <= '0';
                if tx_period_cnt = TX_PERIOD - 1 then
                    tx_period_cnt <= 0;
                    if tx_busy = '0' then
                        tx_start <= '1';
                    end if;
                else
                    tx_period_cnt <= tx_period_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 3. UART TRANSMITTER
    --------------------------------------------------------------------------
    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then
            if RST_SW = '0' then
                tx_busy    <= '0';
                tx_reg     <= '1';
                tx_bit_cnt <= 0;
                tx_data    <= (others => '0');
            else
                if tx_start = '1' then
                    tx_data    <= TEST_BYTE;
                    tx_busy    <= '1';
                    tx_reg     <= '0'; -- Start Bit
                    tx_bit_cnt <= 0;
                elsif (baud_tick = '1') and (tx_busy = '1') then
                    case tx_bit_cnt is
                        when 0 to 7 =>
                            tx_reg     <= tx_data(tx_bit_cnt);
                            tx_bit_cnt <= tx_bit_cnt + 1;
                        when 8 =>
                            tx_reg     <= '1'; -- Stop Bit
                            tx_bit_cnt <= 9;
                        when 9 =>
                            tx_busy    <= '0';
                            tx_bit_cnt <= 0;
                        when others =>
                            tx_busy    <= '0';
                            tx_bit_cnt <= 0;
                    end case;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- 4. UART RECEIVER
    --------------------------------------------------------------------------
    process(FPGA_CLK_50MHZ)
    begin
        if rising_edge(FPGA_CLK_50MHZ) then
            if RST_SW = '0' then
                rx_state      <= RX_IDLE;
                rx_sample_cnt <= 0;
                rx_bit_cnt    <= 0;
                rx_shift      <= (others => '0');
                rx_byte       <= (others => '0');
                test_ok       <= '0';
                rx_error      <= '0';
                rx_sync1      <= '1';
                rx_sync2      <= '1';
            else
                -- Synchronizer Flip-Flops for Asynchronous Input
                rx_sync1 <= RS422_RX;
                rx_sync2 <= rx_sync1;

                case rx_state is

                    when RX_IDLE =>
                        rx_sample_cnt <= 0;
                        rx_bit_cnt    <= 0;
                        if rx_sync2 = '0' then
                            rx_state <= RX_START;
                        end if;

                    when RX_START =>
                        if rx_sample_cnt = HALF_BAUD - 1 then
                            rx_sample_cnt <= 0;
                            if rx_sync2 = '0' then
                                rx_state <= RX_DATA;
                            else
                                rx_state <= RX_IDLE;
                            end if;
                        else
                            rx_sample_cnt <= rx_sample_cnt + 1;
                        end if;

                    when RX_DATA =>
                        if rx_sample_cnt = BAUD_TICKS - 1 then
                            rx_sample_cnt <= 0;
                            rx_shift(rx_bit_cnt) <= rx_sync2;
                            if rx_bit_cnt = 7 then
                                rx_bit_cnt <= 0;
                                rx_state   <= RX_STOP;
                            else
                                rx_bit_cnt <= rx_bit_cnt + 1;
                            end if;
                        else
                            rx_sample_cnt <= rx_sample_cnt + 1;
                        end if;

                    when RX_STOP =>
                        if rx_sample_cnt = BAUD_TICKS - 1 then
                            rx_sample_cnt <= 0;
                            if rx_sync2 = '1' then
                                rx_byte  <= rx_shift;
                                rx_error <= '0';

                                if rx_shift = TEST_BYTE then
                                    test_ok <= '1';
                                else
                                    test_ok <= '0';
                                end if;
                            else
                                rx_error <= '1';
                                test_ok  <= '0';
                            end if;
                            rx_state <= RX_IDLE;
                        else
                            rx_sample_cnt <= rx_sample_cnt + 1;
                        end if;

                    when others =>
                        rx_state      <= RX_IDLE;
                        rx_sample_cnt <= 0;
                        rx_bit_cnt    <= 0;

                end case;
            end if;
        end if;
    end process;

end Behavioral;