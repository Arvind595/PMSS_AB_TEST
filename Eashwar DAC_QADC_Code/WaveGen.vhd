----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04.03.2026 20:08:27
-- Design Name: 
-- Module Name: WaveGen - Behavioral
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
entity WaveGen is
    Port (  
            rstn      : in std_logic;
            lclk        : in std_logic; --33MHZ
            ladd       : in std_logic_vector(11 downto 2);        
            lwrn        : in std_logic;
            blastn      : in std_logic;
            csn         : in std_logic;
            clk_50m     : in std_logic; --50MHz
            ldata       : in std_logic_vector(31 downto 0);

            -- Physical QSPI Bus
            spi_sclk       : out STD_LOGIC;
            spi_io         : inout STD_LOGIC_VECTOR(3 downto 0);
            spi_cs_n       : out STD_LOGIC;
            ldac_n         : out std_logic;
            dac_rstn       : out std_logic;  
            -- Amplitude mux select
            mux_sel    : out std_logic_vector(1 downto 0);
            master_en  : in  std_logic;
            -- Single-cycle pulse (50 MHz domain) from main_ic1's global CDC.
            -- Resets all GainSine phase accumulators simultaneously.
            phase_sync : in  std_logic

);
end WaveGen;

architecture Behavioral of WaveGen is

    signal soft_rst : std_logic;
    signal rst_int : std_logic;
    signal vout_range : std_logic_vector(3 downto 0) := x"0";
    signal dac_config_flag : std_logic;
    signal mod_index : std_logic_vector(31 downto 0) := (others => '0');
    signal amplitude : std_logic_vector(15 downto 0) := (others => '0');
    signal dac_cmd  : std_logic_vector(15 downto 0) := (others => '0');
    signal start_sine_flag : std_logic;
    signal start_dc_flag : std_logic;
    signal dac_config_50m : std_logic;
    signal start_tx : std_logic;

    signal spi_data_in   : STD_LOGIC_VECTOR(23 downto 0); -- TX payload, MSB first
    signal NIBBLES_TO_TX : integer range 0 to 7;           -- Number of 4-bit nibbles
    signal READY         : STD_LOGIC;                      -- Ready for next frame

    signal start_sine_50m : std_logic;
    signal start_dc_50m : std_logic;
    signal spi_csn_int   : std_logic;
    signal spi_keep_csn  : std_logic;
    signal mod_index_50m : std_logic_vector(31 downto 0) := (others => '0');
    signal amplitude_50m : std_logic_vector(15 downto 0) := (others => '0');
    signal rst_int_50m : std_logic;
begin
   
    xpm_cdc_async_rst_inst : xpm_cdc_async_rst
   generic map (
      DEST_SYNC_FF => 4,    -- DECIMAL; range: 2-10
      INIT_SYNC_FF => 0,    -- DECIMAL; 0=disable simulation init values, 1=enable simulation init values
      RST_ACTIVE_HIGH => 0  -- DECIMAL; 0=active low reset, 1=active high reset
   )
   port map (
      dest_arst => rst_int_50m, -- 1-bit output: src_arst asynchronous reset signal synchronized to destination
                              -- clock domain. This output is registered. NOTE: Signal asserts asynchronously
                              -- but deasserts synchronously to dest_clk. Width of the reset signal is at least
                              -- (DEST_SYNC_FF*dest_clk) period.

      dest_clk => clk_50m,   -- 1-bit input: Destination clock.
      src_arst => rst_int    -- 1-bit input: Source asynchronous reset signal.
   );

-- CDC for dac_config_flag to dac_config_50m domain
xpm_cdc_single_dconf :  xpm_cdc_single
    generic map (
        DEST_SYNC_FF   => 2,        -- 2-stage synchronizer (default for safety)
        INIT_SYNC_FF   => 0,        -- Initial sync FF value (0)
        SIM_ASSERT_CHK => 0,        -- Disable simulation assertions (set to 1 for debug)
        SRC_INPUT_REG  => 1         -- Register input in source domain (reduces metastability risk)
    )
    port map (
        src_clk  => lclk,           -- Source clock
        dest_clk => clk_50m,        -- Destination clock
        src_in   => dac_config_flag,-- Input from lclk domain
        dest_out => dac_config_50m  -- Output to clk_50m domain
    );

    -- CDC for start_sine_flag to start_sine_50m domain
xpm_cdc_single_singen :  xpm_cdc_single
    generic map (
        DEST_SYNC_FF   => 2,        -- 2-stage synchronizer (default for safety)
        INIT_SYNC_FF   => 0,        -- Initial sync FF value (0)
        SIM_ASSERT_CHK => 0,        -- Disable simulation assertions (set to 1 for debug)
        SRC_INPUT_REG  => 1         -- Register input in source domain (reduces metastability risk)
    )
    port map (
        src_clk  => lclk,           -- Source clock
        dest_clk => clk_50m,        -- Destination clock
        src_in   => start_sine_flag,-- Input from lclk domain
        dest_out => start_sine_50m  -- Output to clk_50m domain
    );

   xpm_cdc_single_dcgen :  xpm_cdc_single
    generic map (
        DEST_SYNC_FF   => 2,        -- 2-stage synchronizer (default for safety)
        INIT_SYNC_FF   => 0,        -- Initial sync FF value (0)
        SIM_ASSERT_CHK => 0,        -- Disable simulation assertions (set to 1 for debug)
        SRC_INPUT_REG  => 1         -- Register input in source domain (reduces metastability risk)
    )
    port map (
        src_clk  => lclk,           -- Source clock
        dest_clk => clk_50m,        -- Destination clock
        src_in   => start_dc_flag,-- Input from lclk domain
        dest_out => start_dc_50m  -- Output to clk_50m domain
    );

    xpm_cdc_arr_amp : xpm_cdc_array_single
		generic map (
			DEST_SYNC_FF   => 4,   -- DECIMAL; range: 2-10
			INIT_SYNC_FF   => 0,   -- DECIMAL; 0=disable simulation init values, 1=enable simulation init values
			SIM_ASSERT_CHK => 0,   -- DECIMAL; 0=disable simulation messages, 1=enable simulation messages
			SRC_INPUT_REG  => 1,   -- DECIMAL; 0=do not register input, 1=register input
			WIDTH          => 16   -- DECIMAL; range: 1-1024
		)
		port map (
			dest_out => amplitude_50m, -- WIDTH-bit output: src_in synchronized to destination clock domain
			dest_clk => clk_50m,         -- 1-bit input: destination clock
			src_clk  => lclk,            -- 1-bit input: source clock (required when SRC_INPUT_REG = 1)
			src_in   => amplitude      -- WIDTH-bit input: input bus to be synchronized
		);

    xpm_cdc_arr_modindex : xpm_cdc_array_single
		generic map (
			DEST_SYNC_FF   => 4,   -- DECIMAL; range: 2-10
			INIT_SYNC_FF   => 0,   -- DECIMAL; 0=disable simulation init values, 1=enable simulation init values
			SIM_ASSERT_CHK => 0,   -- DECIMAL; 0=disable simulation messages, 1=enable simulation messages
			SRC_INPUT_REG  => 1,   -- DECIMAL; 0=do not register input, 1=register input
			WIDTH          => 32   -- DECIMAL; range: 1-1024
		)
		port map (
			dest_out => mod_index_50m, -- WIDTH-bit output: src_in synchronized to destination clock domain
			dest_clk => clk_50m,         -- 1-bit input: destination clock
			src_clk  => lclk,            -- 1-bit input: source clock (required when SRC_INPUT_REG = 1)
			src_in   => mod_index      -- WIDTH-bit input: input bus to be synchronized
		);

    SPI_IP : SPIMaster
        port map (
            CLK_50M       => clk_50m,
            RST_N         => rst_int_50m,
            START_TX      => start_tx,
            DATA_IN       => spi_data_in,
            NIBBLES_TO_TX => NIBBLES_TO_TX,
            IS_READ       => '0',
            KEEP_CSN_LOW  => spi_keep_csn,
            DATA_OUT      => open,
            READY         => READY,
            SCLK          => spi_sclk,
            IO            => spi_io,
            CS_N          => spi_csn_int
        );


    DAC_CONFIG_IP : DAC_CONFIG
        port map (
            rstn         => rst_int_50m,
            clk_50m      => clk_50m,
            config_en    => dac_config_50m,
            start_dc     => start_dc_50m,
            start_sine   => start_sine_50m,
            phase_sync   => phase_sync,
            user_gain    => amplitude_50m,
            mod_index    => mod_index_50m,
            spi_start    => start_tx,
            spi_data     => spi_data_in,
            spi_bits     => NIBBLES_TO_TX,
            spi_keep_csn => spi_keep_csn,
            spi_ready    => READY,
            ldac_n       => ldac_n
        );

    spi_cs_n <= spi_csn_int;

    dac_rstn <= rst_int;

    soft_rst <= '0' when(csn = '0' and ladd(11 downto 2) = DAC_RST_ADDR) else '1';

    rst_int <= rstn and soft_rst;

    --dac_config_flag <= '1' when(csn = '0' and ladd(11 downto 2) = DAC_CONFIG_ADDR and lwrn = '1' and blastn = '0') else '0';

    --dac_config_flag <= '1' when(csn = '0' and ladd(11 downto 2) = DAC_CONFIG_ADDR) else '0';

    -- process(lclk, rst_int)
    -- begin
    --     if(rising_edge(lclk)) then
    --         if(rst_int = '0') then
    --             vout_range <= x"0";
    --             mod_index <= (others => '0');
    --             amplitude <= (others => '0');
    --             dac_cmd <= (others => '0');
    --         else
    --             if(lwrn = '1' and csn = '0' and blastn = '0' and ladd(11 downto 2) =  DAC_VOUT_ADDR)then
    --                 vout_range <= ldata(3 downto 0);
    --             elsif(lwrn = '1' and csn = '0' and blastn = '0' and ladd(11 downto 2) = DAC_CMD_ADDR)then
    --                 dac_cmd <= ldata(15 downto 0);
    --             elsif(lwrn = '1' and csn = '0' and blastn = '0' and ladd(11 downto 2) = DAC_AMP_ADDR)then
    --                 amplitude <= ldata(15 downto 0);
    --             elsif(lwrn = '1' and csn = '0' and blastn = '0' and ladd(11 downto 2) = DAC_MOD_ADDR) then
    --                 mod_index(31 downto 0) <= ldata;
    --             end if;
    --         end if;
    --     end if;
    -- end process;

    process(lclk, rst_int)
    begin
        if(rising_edge(lclk)) then
            if(rst_int = '0') then
                vout_range <= x"0";
                mod_index <= (others => '0');
                amplitude <= (others => '0');
                dac_cmd <= (others => '0');
            else
                if(csn = '0' and ladd(11 downto 2) =  DAC_VOUT_ADDR)then
                    vout_range <= ldata(3 downto 0);
                elsif(csn = '0' and ladd(11 downto 2) = DAC_CMD_ADDR)then
                    dac_cmd <= ldata(15 downto 0);
                elsif(csn = '0' and ladd(11 downto 2) = DAC_AMP_ADDR)then
                    amplitude <= ldata(15 downto 0);
                elsif(csn = '0' and ladd(11 downto 2) = DAC_MOD_ADDR) then
                    mod_index(31 downto 0) <= ldata;
                elsif(csn = '0' and ladd(11 downto 2) = DAC_CONFIG_ADDR) then
                    dac_config_flag <= ldata(0);    
                end if;
            end if;
        end if;
    end process;


    mux_sel <= "00" when (vout_range = x"0" or vout_range = x"1") else
               "01" when (vout_range = x"2" or vout_range = x"3") else
               "10";

    start_sine_flag <= '1' when (dac_cmd(7 downto 0) = x"55" and master_en = '1') else '0';

    start_dc_flag <= '1' when (dac_cmd(7 downto 0) = x"56" and master_en = '1') else '0';
  
                        



end Behavioral;
