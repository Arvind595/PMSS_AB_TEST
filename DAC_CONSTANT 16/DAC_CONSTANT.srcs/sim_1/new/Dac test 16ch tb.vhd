--------------------------------------------------------------------------------
-- dac_test_16ch_tb.vhd
--
-- Self-checking testbench for dac_test_16ch.vhd (16x dac_ad3551r_ch.vhd).
--
-- For each of the 16 independent channels, this testbench:
--   1) Checks the DAC_nRST pulse is released ~100us after RST_SW is deasserted.
--   2) Captures the 3 SPI frames each channel sends at startup (power-up,
--      range-select, DAC data write) by sniffing DAC_nCS/DAC_SCLK/DAC_SDIO0,
--      and checks each frame's bit-count and content against the expected
--      register writes.
--   3) Checks the static tie-off signals (DAC_nLOAD, DAC_SDIO2/3, BUS_DATA,
--      TP_CLK_TST) stay at their expected constant values.
--
-- EXPECTED_DAC_CODE below mirrors the CH_DAC_CODE table in dac_test_16ch.vhd
-- (currently all 0x8000 / 0V). If you edit CH_DAC_CODE in the design, update
-- EXPECTED_DAC_CODE here to match, or the per-channel DAC-write checks below
-- will report mismatches.
--
-- Requires VHDL-2008 (uses to_hstring and integer'image). In Vivado, if your
-- project's default language is VHDL-93/2002, set this file's "File Type" to
-- VHDL 2008 in Source File Properties (simulation-only files can differ from
-- the synthesis language setting).
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity dac_test_16ch_tb is
end dac_test_16ch_tb;

architecture behavior of dac_test_16ch_tb is

    constant CLK_PERIOD : time := 20 ns; -- 50 MHz

    -- Must match dac_test_16ch.vhd
    constant RANGE_CODE : std_logic_vector(7 downto 0) := x"04";

    type code_array_t is array (0 to 15) of std_logic_vector(15 downto 0);
    -- Mirrors CH_DAC_CODE in dac_test_16ch.vhd -- keep in sync
    constant EXPECTED_DAC_CODE : code_array_t := (
         0 => x"8CCC",  -- CH00 = 1.000 V
         1 => x"BFFF",  -- CH01 = 5.000 V
         2 => x"9333",  -- CH02 = 1.500 V
         3 => x"C666",  -- CH03 = 5.500 V
         4 => x"9999",  -- CH04 = 2.000 V
         5 => x"CCCC",  -- CH05 = 6.000 V
         6 => x"9FFF",  -- CH06 = 2.500 V
         7 => x"D332",  -- CH07 = 6.500 V
         8 => x"A666",  -- CH08 = 3.000 V
         9 => x"D999",  -- CH09 = 7.000 V
        10 => x"ACCC",  -- CH10 = 3.500 V
        11 => x"E666",  -- CH11 = 8.000 V
        12 => x"B333",  -- CH12 = 4.000 V
        13 => x"F332",  -- CH13 = 9.000 V
        14 => x"B999",  -- CH14 = 4.500 V
        15 => x"FFFF"  -- CH15 = 10.000 V
    );
    -- Full 24-bit frames expected on the wire (MSB-first), independent of channel
    constant EXP_FRAME_PWR : std_logic_vector(23 downto 0) := x"001800"; -- Reg 0x18 <= 0x00
    constant EXP_FRAME_RNG : std_logic_vector(23 downto 0) := x"00" & x"19" & RANGE_CODE; -- Reg 0x19 <= RANGE_CODE

    -- DUT I/O
    signal RST_SW         : std_logic := '0';
    signal FPGA_CLK_50MHZ : std_logic := '0';
    signal TP_CLK_TST     : std_logic;
    signal STS1_LED_GREEN : std_logic;
    signal DAC_nRST       : std_logic_vector(15 downto 0);
    signal DAC_nLOAD      : std_logic_vector(15 downto 0);
    signal DAC_nCS        : std_logic_vector(15 downto 0);
    signal DAC_SCLK       : std_logic_vector(15 downto 0);
    signal DAC_SDIO0      : std_logic_vector(15 downto 0);
    signal DAC_SDIO2      : std_logic_vector(15 downto 0);
    signal DAC_SDIO3      : std_logic_vector(15 downto 0);
    signal BUS_DATA       : std_logic_vector(15 downto 0);

    -- Per-channel completion / failure flags for the pass/fail scoreboard
    signal ch_done : std_logic_vector(15 downto 0) := (others => '0');
    signal ch_fail : std_logic_vector(15 downto 0) := (others => '0');

begin

    ----------------------------------------------------------------------------
    -- UUT
    ----------------------------------------------------------------------------
    uut: entity work.dac_test_16ch
        generic map (
            SIM_MODE => true
        )
        port map (
            RST_SW         => RST_SW,
            FPGA_CLK_50MHZ => FPGA_CLK_50MHZ,
            TP_CLK_TST     => TP_CLK_TST,
            STS1_LED_GREEN => STS1_LED_GREEN,
            DAC_nRST       => DAC_nRST,
            DAC_nLOAD      => DAC_nLOAD,
            DAC_nCS        => DAC_nCS,
            DAC_SCLK       => DAC_SCLK,
            DAC_SDIO0      => DAC_SDIO0,
            DAC_SDIO2      => DAC_SDIO2,
            DAC_SDIO3      => DAC_SDIO3,
            BUS_DATA       => BUS_DATA
        );

    ----------------------------------------------------------------------------
    -- Clock
    ----------------------------------------------------------------------------
    clk_process : process
    begin
        FPGA_CLK_50MHZ <= '0';
        wait for CLK_PERIOD/2;
        FPGA_CLK_50MHZ <= '1';
        wait for CLK_PERIOD/2;
    end process;

    ----------------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------------
    stim_proc : process
    begin
        RST_SW <= '0';
        wait for 100 ns;
        RST_SW <= '1';

        -- All 16 channels finish their init sequence well inside ~120us
        -- (SIM_MODE shortens the WAIT_RDY delay). Give generous margin.
        wait for 300 us;

        report "--------------------------------------------------------------";
        if ch_done /= (ch_done'range => '1') then
            report "TESTBENCH RESULT: FAIL - incomplete channels, ch_done = "
                   & to_hstring(ch_done) severity error;
        elsif ch_fail /= (ch_fail'range => '0') then
            report "TESTBENCH RESULT: FAIL - channel(s) with errors, ch_fail = "
                   & to_hstring(ch_fail) severity error;
        else
            report "TESTBENCH RESULT: ALL 16 CHANNELS PASSED" severity note;
        end if;
        report "--------------------------------------------------------------";

        std.env.stop;
    end process;

    ----------------------------------------------------------------------------
    -- Per-channel SPI monitor + checker
    ----------------------------------------------------------------------------
    gen_monitors : for i in 0 to 15 generate

        -- Captures one MSB-first SPI frame: waits for nCS low, shifts in SDIO0
        -- on every SCLK rising edge while nCS stays low, returns the captured
        -- bits right-aligned in a 24-bit word plus how many bits were seen.
        procedure capture_frame(
            signal ncs    : in  std_logic;
            signal sclk   : in  std_logic;
            signal sdio   : in  std_logic;
            variable word  : out std_logic_vector(23 downto 0);
            variable nbits : out integer
        ) is
            variable shreg : std_logic_vector(23 downto 0) := (others => '0');
            variable cnt   : integer := 0;
        begin
            wait until ncs = '0';
            shreg := (others => '0');
            cnt   := 0;
            while ncs = '0' loop
                wait until rising_edge(sclk) or ncs'event;
                if ncs = '0' then
                    shreg := shreg(22 downto 0) & sdio;
                    cnt   := cnt + 1;
                end if;
            end loop;
            word  := shreg;
            nbits := cnt;
        end procedure;

    begin

        monitor_proc : process
            variable t0, t1              : time;
            variable w_pwr, w_rng, w_dac : std_logic_vector(23 downto 0);
            variable n_pwr, n_rng, n_dac : integer;
            variable rst_ok, pwr_ok, rng_ok, dac_ok, ok : boolean;
            constant exp_dac : std_logic_vector(23 downto 0) := x"2A" & EXPECTED_DAC_CODE(i);
        begin
            -- 1) Reset pulse timing
            wait until RST_SW = '1';
            t0 := now;
            wait until DAC_nRST(i) = '1';
            t1 := now;
            rst_ok := (t1 - t0) >= 99 us and (t1 - t0) <= 101 us;
            assert rst_ok
                report "CH" & integer'image(i) & ": DAC_nRST release timing out of "
                       & "expected ~100us window (measured " & time'image(t1 - t0) & ")"
                severity error;

            -- 2) Power-up frame: Reg 0x18 <= 0x00
            capture_frame(DAC_nCS(i), DAC_SCLK(i), DAC_SDIO0(i), w_pwr, n_pwr);
            pwr_ok := (n_pwr = 16) and (w_pwr = EXP_FRAME_PWR);
            assert pwr_ok
                report "CH" & integer'image(i) & ": power frame = 0x" & to_hstring(w_pwr)
                       & " (" & integer'image(n_pwr) & " bits), expected 0x"
                       & to_hstring(EXP_FRAME_PWR) & " (16 bits)"
                severity error;

            -- 3) Range-select frame: Reg 0x19 <= RANGE_CODE
            capture_frame(DAC_nCS(i), DAC_SCLK(i), DAC_SDIO0(i), w_rng, n_rng);
            rng_ok := (n_rng = 16) and (w_rng = EXP_FRAME_RNG);
            assert rng_ok
                report "CH" & integer'image(i) & ": range frame = 0x" & to_hstring(w_rng)
                       & " (" & integer'image(n_rng) & " bits), expected 0x"
                       & to_hstring(EXP_FRAME_RNG) & " (16 bits)"
                severity error;

            -- 4) DAC data-write frame: Reg 0x2A <= EXPECTED_DAC_CODE(i)
            capture_frame(DAC_nCS(i), DAC_SCLK(i), DAC_SDIO0(i), w_dac, n_dac);
            dac_ok := (n_dac = 24) and (w_dac = exp_dac);
            assert dac_ok
                report "CH" & integer'image(i) & ": DAC-write frame = 0x" & to_hstring(w_dac)
                       & " (" & integer'image(n_dac) & " bits), expected 0x"
                       & to_hstring(exp_dac) & " (24 bits)"
                severity error;

            ok := rst_ok and pwr_ok and rng_ok and dac_ok;
            if ok then
                report "CH" & integer'image(i) & ": PASS (reset timing OK, power/range/DAC frames verified)"
                    severity note;
            else
                report "CH" & integer'image(i) & ": FAIL - see error(s) above" severity error;
                ch_fail(i) <= '1';
            end if;

            ch_done(i) <= '1';
            wait;
        end process;

    end generate gen_monitors;

    ----------------------------------------------------------------------------
    -- Static tie-off checks. Run from a clocked process (not a bare concurrent
    -- assert) so the very first VHDL delta-cycle -- where these signals still
    -- sit at their 'U' initial value, before the DUT's concurrent tie-off
    -- assignments have propagated -- doesn't produce a spurious error at t=0.
    ----------------------------------------------------------------------------
    static_checks_proc : process
    begin
        wait for 1 ns; -- let the t=0 initialization deltas settle first
        loop
            wait until rising_edge(FPGA_CLK_50MHZ);

            assert BUS_DATA = x"AAAA"
                report "BUS_DATA drifted from expected constant 0xAAAA" severity error;
            assert TP_CLK_TST = DAC_SCLK(0)
                report "TP_CLK_TST does not mirror channel 0 SCLK" severity error;

            for i in 0 to 15 loop
                assert DAC_nLOAD(i) = '0'
                    report "CH" & integer'image(i) & ": DAC_nLOAD expected constant '0'" severity error;
                assert DAC_SDIO2(i) = '0'
                    report "CH" & integer'image(i) & ": DAC_SDIO2 expected constant '0'" severity error;
                assert DAC_SDIO3(i) = '0'
                    report "CH" & integer'image(i) & ": DAC_SDIO3 expected constant '0'" severity error;
            end loop;
        end loop;
    end process;

    ----------------------------------------------------------------------------
    -- Watchdog: flag incomplete channels well before the stimulus timeout
    ----------------------------------------------------------------------------
    watchdog_proc : process
    begin
        wait for 250 us;
        if ch_done /= (ch_done'range => '1') then
            report "WATCHDOG: not all channels completed within 250us, ch_done = "
                   & to_hstring(ch_done) severity error;
        end if;
        wait;
    end process;

end behavior;