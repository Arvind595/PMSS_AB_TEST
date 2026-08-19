library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity DAC_RESET_ALL_TB is
end DAC_RESET_ALL_TB;

architecture Behavioral of DAC_RESET_ALL_TB is

    -- DUT signals
    signal BRST : STD_LOGIC_VECTOR(15 downto 0);
	signal BCS : STD_LOGIC_VECTOR(15 downto 0);
	signal BSDIO3 : STD_LOGIC_VECTOR(15 downto 0);
	signal BSDIO2 : STD_LOGIC_VECTOR(15 downto 0);

begin

    -- Instantiate Device Under Test
    DUT : entity work.DAC_RESET_ALL
        port map (
            BRST => BRST,
			BCS => BCS,
			BSDIO2 =>BSDIO2,
			BSDIO3 =>BSDIO3
			
        );

    -- Test process
    process
    begin

        -- Wait for DUT to settle
        wait for 10 ns;

        -- Verify all 16 pins are LOW
        assert BRST = "0000000000000000"
            report "ERROR: Not all BRST pins are 0!"
            severity error;

        report "PASS: All 16 BRST pins are 0."
            severity note;
        -- Verify all 16 pins are LOW
        assert BCS = "1111111111111111"
            report "ERROR: Not all BCS pins are 1!"
            severity error;

        report "PASS: All 16 BCS pins are 1."
            severity note;	
			
        -- Verify all 16 pins are LOW
        assert BSDIO3 = "0000000000000000"
            report "ERROR: Not all BSDIO3 pins are 0!"
            severity error;

        report "PASS: All 16 BSDIO3 pins are 0."
            severity note;			

        -- Verify all 16 pins are LOW
        assert BSDIO2 = "0000000000000000"
            report "ERROR: Not all BSDIO2 pins are 0!"
            severity error;

        report "PASS: All 16 BSDIO2 pins are 0."
            severity note;	

        wait;

    end process;

end Behavioral;
