----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05.03.2026 18:02:40
-- Design Name: 
-- Module Name: GainSine - Behavioral
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
use IEEE.NUMERIC_STD.ALL;
use work.sine_lut_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity GainSine is
   Port ( 
        clk_50mhz      : in  STD_LOGIC;
        reset          : in  STD_LOGIC;
        
        -- User Input: 0 to 65535 (0% to 100% Amplitude)
        user_gain      : in  std_logic_vector(15 downto 0);
        mod_index      : in  std_logic_vector(31 downto 0); -- For future use (e.g. to select different waveforms or frequencies) 
        start_gen      : in  STD_LOGIC;  -- Trigger to start sine wave generation
        phase_sync     : in  STD_LOGIC;  -- Pulse: resets phase to 0 on all channels simultaneously
        dac_data_out   : out STD_LOGIC_VECTOR (15 downto 0);
        new_data_ready : out STD_LOGIC;
        new_data_ack   : in  STD_LOGIC
    );
end GainSine;

architecture Behavioral of GainSine is
  -- 1. Sample Rate Divider: sg3 runs (C_SAMPLE_DIV-1) cycles + 1 cycle in sg2 = C_SAMPLE_DIV cycles total.
    --    To achieve exactly 1 MHz (50 cycles @ 50 MHz): C_SAMPLE_DIV = 49.
    constant C_SAMPLE_DIV     : unsigned(7 downto 0) := to_unsigned(49, 8);
    signal sample_counter     : unsigned(7 downto 0) := (others => '0');

    -- 2. DDS Parameters (Sub-0.1Hz accuracy)
    constant C_ACCUM_BITS     : natural := 32;
    -- M = (1300 * 2^32) / 1,000,000 = 5,583,457
    --constant C_INCREMENT      : unsigned(31 downto 0) := to_unsigned(5583457, 32);
    signal phase_accum        : unsigned(31 downto 0) := (others => '0');
    
    -- 3. LUT Interface
    signal lut_addr           : unsigned(9 downto 0) := (others => '0');
    constant OFFSET      : signed(16 downto 0) := to_signed(32768, 17);
    signal raw_sine      : signed(16 downto 0) := (others => '0'); -- 17 bits to avoid overflow during sub
    signal signed_gain   : signed(16 downto 0) := (others => '0');
    signal mult_result   : signed(33 downto 0) := (others => '0');

    type state_gen is (sg1, sg2, sg3, sg4);
    signal current_state_gen : state_gen := sg1;

    signal temp_data : std_logic_vector(15 downto 0) := (others => '0');
    signal data_ready : std_logic := '0';

    signal user_gain_int : unsigned(15 downto 0);
    signal mod_index_int : unsigned(31 downto 0);
begin


    user_gain_int <= unsigned(user_gain);
    mod_index_int <= unsigned(mod_index);


    dac_data_out <= temp_data;
    new_data_ready <= data_ready;
    
    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if reset = '0' then
                current_state_gen <= sg1;
                phase_accum <= (others => '0');
                sample_counter <= (others => '0');
                data_ready <= '0';
                temp_data <= (others => '0');
                sample_counter <= (others => '0');
                lut_addr <= (others => '0');
                raw_sine <= (others => '0');
                signed_gain <= (others => '0');
                mult_result <= (others => '0');
            -- phase_sync: highest priority override.
            -- Asserted from a SINGLE CDC in main_ic1 so ALL channels see it on
            -- the IDENTICAL 50 MHz clock edge → guaranteed zero-crossing alignment.
            elsif phase_sync = '1' then
                phase_accum        <= (others => '0');
                sample_counter     <= (others => '0');
                lut_addr           <= (others => '0');
                data_ready         <= '0';
                raw_sine           <= (others => '0');
                signed_gain        <= (others => '0');
                mult_result        <= (others => '0');
                -- Go to sg2 immediately: generate first sample (sin=0) this cycle.
                current_state_gen  <= sg2;
            else
                case current_state_gen is
                    when sg1 =>
                        if(start_gen = '1') then
                            current_state_gen <= sg2;
                        else
                            current_state_gen <= sg1;
                        end if;

                    when sg2 =>
                        -- Map Top 10 bits of Accumulator to 1024-entry LUT
                        lut_addr <= phase_accum(31 downto 22);
                        -- 1. Get raw data from LUT and convert to signed (center at 0)
                        raw_sine <= signed('0' & SINE_LUT(to_integer(lut_addr))) - OFFSET;
                        -- 2. Convert user gain to signed format for multiplication
                        signed_gain <= signed('0' & user_gain_int);
                        -- 3. Multiply (Artix-7 will use a DSP slice here)
                        mult_result <= raw_sine * signed_gain;
                        temp_data <= std_logic_vector(unsigned(mult_result(31 downto 16) + OFFSET(15 downto 0)));
                        data_ready <= '1';
                        current_state_gen <= sg3;

                    when sg3 =>
                        if(start_gen = '1')then
                            if(sample_counter = C_SAMPLE_DIV - 1) then
                                sample_counter <= (others => '0');
                                --phase_accum <= phase_accum + C_INCREMENT;
                                 phase_accum <= phase_accum + mod_index_int; -- For future use (e.g. to select different waveforms or frequencies)
                                current_state_gen <= sg2;
                            else
                                sample_counter <= sample_counter + 1;
                                current_state_gen <= sg3;
                            end if;

                            if(new_data_ack = '1' and data_ready = '1') then
                                data_ready <= '0';
                             end if;
                        else
                            current_state_gen <= sg1;
                            sample_counter <= (others => '0');
                            phase_accum <= (others => '0');
                            data_ready <= '0';
                            lut_addr <= (others => '0');
                            raw_sine <= (others => '0');
                            signed_gain <= (others => '0');
                            mult_result <= (others => '0');
                        end if;
                    
                    when others =>
                        current_state_gen <= sg1;
                        phase_accum <= (others => '0');
                        sample_counter <= (others => '0');
                        data_ready <= '0';
                        temp_data <= (others => '0');
                        sample_counter <= (others => '0');
                        lut_addr <= (others => '0');
                        raw_sine <= (others => '0');
                        signed_gain <= (others => '0');
                        mult_result <= (others => '0');
                end case;
            end if;
        end if;
    end process;

                    
end Behavioral;
