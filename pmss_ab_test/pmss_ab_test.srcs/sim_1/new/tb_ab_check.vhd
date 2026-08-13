library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_ab_check is
-- Testbench entities do not have ports
end tb_ab_check;

architecture behavior of tb_ab_check is

    --------------------------------------------------------------------------
    -- COMPONENT DECLARATION
    --------------------------------------------------------------------------
    component ab_check
        Port ( 
            RST_SW          : in  STD_LOGIC; -- On-Board Active-Low Reset Switch
            FPGA_CLK_50MHZ  : in  STD_LOGIC;
            TP_CLK_TST      : out STD_LOGIC;
            STS1_LED_GREEN  : out STD_LOGIC;
            STS2_LED_YELLOW : out STD_LOGIC;
            RS422_RX        : in  STD_LOGIC;
            RS422_TX        : out STD_LOGIC;
            RS422_TX_EN     : out STD_LOGIC;
            RS422_TX_nEN    : out STD_LOGIC
        );
    end component;

    --------------------------------------------------------------------------
    -- SIGNAL DECLARATIONS
    --------------------------------------------------------------------------
    -- Inputs
    signal RST_SW          : std_logic := '0'; -- Start in reset state (Active-Low)
    signal FPGA_CLK_50MHZ  : std_logic := '0';
    signal RS422_RX        : std_logic := '1'; -- Idle state is logic HIGH

    -- Outputs
    signal TP_CLK_TST      : std_logic;
    signal STS1_LED_GREEN  : std_logic;
    signal STS2_LED_YELLOW : std_logic;
    signal RS422_TX        : std_logic;
    signal RS422_TX_EN     : std_logic;
    signal RS422_TX_nEN    : std_logic;

    --------------------------------------------------------------------------
    -- CONSTANTS & TIMING DEFINITIONS
    --------------------------------------------------------------------------
    -- 50 MHz Clock Period = 20 ns
    constant CLK_PERIOD    : time := 20 ns; 
    
    -- 115200 Baud Period = 434 clock ticks * 20 ns = 8680 ns
    constant BAUD_PERIOD   : time := 8680 ns; 

begin

    --------------------------------------------------------------------------
    -- UNIT UNDER TEST (UUT) INSTANTIATION
    --------------------------------------------------------------------------
    uut: ab_check
        Port Map (
            RST_SW          => RST_SW,
            FPGA_CLK_50MHZ  => FPGA_CLK_50MHZ,
            TP_CLK_TST      => TP_CLK_TST,
            STS1_LED_GREEN  => STS1_LED_GREEN,
            STS2_LED_YELLOW => STS2_LED_YELLOW,
            RS422_RX        => RS422_RX,
            RS422_TX        => RS422_TX,
            RS422_TX_EN     => RS422_TX_EN,
            RS422_TX_nEN    => RS422_TX_nEN
        );

    --------------------------------------------------------------------------
    -- 50 MHz CLOCK GENERATOR PROCESS
    --------------------------------------------------------------------------
    clk_process : process
    begin
        FPGA_CLK_50MHZ <= '0';
        wait for CLK_PERIOD / 2;
        FPGA_CLK_50MHZ <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    --------------------------------------------------------------------------
    -- STIMULUS & VERIFICATION PROCESS
    --------------------------------------------------------------------------
    stim_proc: process

        -- Helper procedure to transmit an 8-bit UART frame over RS422_RX
        procedure send_uart_byte (
            constant data_in : in std_logic_vector(7 downto 0)
        ) is
        begin
            -- Start Bit (LOW)
            RS422_RX <= '0';
            wait for BAUD_PERIOD;

            -- 8 Data Bits (LSB First)
            for i in 0 to 7 loop
                RS422_RX <= data_in(i);
                wait for BAUD_PERIOD;
            end loop;

            -- Stop Bit (HIGH)
            RS422_RX <= '1';
            wait for BAUD_PERIOD;
        end procedure;

    begin
        ----------------------------------------------------------------------
        -- INITIALIZATION & RESET PULSE
        ----------------------------------------------------------------------
        report "INITIALIZATION: Applying active-low reset (RST_SW = '0')...";
        RST_SW   <= '0';
        RS422_RX <= '1';
        wait for 100 ns;

        -- Release Reset
        report "INITIALIZATION: Releasing reset (RST_SW = '1')...";
        RST_SW   <= '1';
        wait for 100 ns;

        ----------------------------------------------------------------------
        -- TEST 1: Send expected test byte (0x55)
        ----------------------------------------------------------------------
        report "TEST 1: Sending correct test byte (0x55)...";
        send_uart_byte(x"55");
        
        -- Wait for receiver state machine to process stop bit
        wait for BAUD_PERIOD * 2;

        assert STS2_LED_YELLOW = '1'
            report "ERROR: STS2_LED_YELLOW failed to turn ON after receiving 0x55!"
            severity error;

        ----------------------------------------------------------------------
        -- TEST 2: Send incorrect test byte (0xAA)
        ----------------------------------------------------------------------
        report "TEST 2: Sending incorrect test byte (0xAA)...";
        send_uart_byte(x"AA");
        
        wait for BAUD_PERIOD * 2;

        assert STS2_LED_YELLOW = '0'
            report "ERROR: STS2_LED_YELLOW failed to turn OFF after receiving non-0x55 byte!"
            severity error;

        ----------------------------------------------------------------------
        -- TEST 3: Resend valid byte (0x55) to confirm recovery
        ----------------------------------------------------------------------
        report "TEST 3: Resending correct test byte (0x55)...";
        send_uart_byte(x"55");
        
        wait for BAUD_PERIOD * 2;

        assert STS2_LED_YELLOW = '1'
            report "ERROR: STS2_LED_YELLOW failed to recover to ON status!"
            severity error;

        ----------------------------------------------------------------------
        -- TEST 4: Assert Reset mid-operation to test hardware reset button
        ----------------------------------------------------------------------
        report "TEST 4: Pressing Reset Switch (RST_SW = '0')...";
        RST_SW <= '0';
        wait for 100 ns;

        assert (STS2_LED_YELLOW = '0' and STS1_LED_GREEN = '0')
            report "ERROR: Signals failed to clear during Reset!"
            severity error;

        report "TEST 4: Releasing Reset Switch (RST_SW = '1')...";
        RST_SW <= '1';
        wait for 100 ns;

        ----------------------------------------------------------------------
        -- SIMULATION COMPLETE
        ----------------------------------------------------------------------
        report "SUCCESS: All test cases completed!";
        wait;
    end process;

end behavior;