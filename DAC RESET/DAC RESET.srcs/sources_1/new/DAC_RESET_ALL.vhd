library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity DAC_RESET_ALL is
    Port (
        BRST : out STD_LOGIC_VECTOR(15 downto 0);
		BCS	 : out STD_LOGIC_VECTOR(15 downto 0);
		BSDIO2	 : out STD_LOGIC_VECTOR(15 downto 0);
		BSDIO3	 : out STD_LOGIC_VECTOR(15 downto 0)
    );
end DAC_RESET_ALL;

architecture Behavioral of DAC_RESET_ALL is

begin

    -- Keep all 16 DAC reset pins LOW
    BRST <= (others => '0');
	BSDIO2 <= (others => '0');
	BSDIO3 <= (others => '0');
	BCS <= (others => '1');

end Behavioral;
