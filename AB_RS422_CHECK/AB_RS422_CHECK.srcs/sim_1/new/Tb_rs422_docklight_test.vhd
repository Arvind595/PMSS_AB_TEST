-------------------------------------------------------------------------------
-- tb_rs422_docklight_test
--
-- Simulates the Docklight (PC) side of rs422_docklight_test.vhd directly at
-- the serial-pin level, full duplex:
--
--   - A dedicated "PC transmit" sequence bit-bangs 8-byte UART frames onto
--     rs422_rx, as Docklight would.
--   - A dedicated, ALWAYS-RUNNING "PC receive" process independently and
--     continuously listens on rs422_tx and decodes whatever bytes the DUT
--     sends back, exactly like a real full-duplex PC UART would. It is not
--     sequenced after the send loop - it's free-running for the whole
--     simulation, so it can never miss the start of an echo that begins
--     while the send loop is still finishing up (the DUT's own baud
--     generator, using truncated integer division, runs at a very slightly
--     different rate than this testbench's derived bit period - realistic,
--     and exactly what a real receiver must tolerate too).
--
-- Four tests:
--   TEST 0 - Boot message: verify the DUT sends its fixed 8-byte boot
--            message (11 22 33 44 55 66 77 88) unprompted, BOOT_DELAY_MS
--            after reset release, before any echo traffic is possible.
--   TEST 1 - Full 8-byte round trip: send a frame, capture the echo,
--            verify byte-for-byte match, and check led_ok pulses.
--   TEST 2 - Timeout recovery: send only 3 of 8 bytes then stop ("PC" goes
--            silent mid-frame, e.g. cable pulled). Verify led_err latches
--            within the TIMEOUT_MS window, and confirm no echo is sent for
--            the incomplete frame.
--   TEST 3 - Recovery: a clean frame sent right after the timeout should
--            echo normally and clear led_err.
--
-- Not covered here (per current scope): back-to-back frames sent before the
-- echo of the previous one finishes (see the "Known assumption" note in
-- rs422_docklight_test.vhd) - can add a follow-up test for that if needed.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rs422_docklight_test is
    -- Testbenches do not have ports
end entity tb_rs422_docklight_test;

architecture sim of tb_rs422_docklight_test is

    -- DUT generics (CLK_FREQ matches the DUT's own default - 27 MHz board clock)
    constant CLK_FREQ       : integer := 27_000_000;
    constant BAUD_RATE      : integer := 115200;
    constant NUM_BYTES      : integer := 8;
    constant TIMEOUT_MS     : integer := 5;
    constant BOOT_DELAY_MS  : integer := 10;  -- must match the DUT's BOOT_DELAY_MS generic
    constant LED_STRETCH_MS : integer := 1;   -- shortened from HW default (1000) so sim doesn't take a full second

    -- Timing
    constant CLK_PERIOD : time := 37.037 ns;         -- ~27 MHz
    constant BIT_PERIOD : time := 1 sec / BAUD_RATE;  -- ~8.68 us per UART bit at 115200 baud

    -- DUT signals
    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';  -- active-low; asserted at sim start
    signal rs422_tx  : std_logic;
    signal rs422_rx  : std_logic := '1';  -- idle high
    signal rs422_en  : std_logic;
    signal rs422_nen : std_logic;
    signal led_ok    : std_logic;
    signal led_err   : std_logic;

    -- Test payloads
    type byte_vec is array (natural range <>) of std_logic_vector(7 downto 0);
    constant TEST1_PAYLOAD : byte_vec(0 to NUM_BYTES-1) :=
        (x"A5", x"02", x"10", x"20", x"30", x"40", x"50", x"60");
    constant TEST2_PAYLOAD : byte_vec(0 to NUM_BYTES-1) :=
        (x"BB", x"02", x"10", x"20", x"30", x"40", x"50", x"60");
    constant BOOT_MSG : byte_vec(0 to NUM_BYTES-1) :=
        (x"11", x"22", x"33", x"44", x"55", x"66", x"77", x"88");

    -- Free-running capture buffer: every byte the DUT ever echoes gets
    -- appended here by capture_proc, independent of what stim_proc is doing.
    constant CAPTURE_DEPTH  : natural := 32;
    signal captured_bytes   : byte_vec(0 to CAPTURE_DEPTH-1);
    signal captured_count   : natural := 0;

    -----------------------------------------------------------------------
    -- Bit-bang a single UART byte out onto a line (simulates Docklight TX)
    -- LSB first, matches uart_phy's bit ordering.
    -----------------------------------------------------------------------
    procedure uart_tx_byte(
        signal   line       : out std_logic;
        constant data       : in  std_logic_vector(7 downto 0);
        constant bit_time   : in  time
    ) is
    begin
        line <= '0';                    -- start bit
        wait for bit_time;
        for i in 0 to 7 loop
            line <= data(i);            -- LSB first
            wait for bit_time;
        end loop;
        line <= '1';                    -- stop bit
        wait for bit_time;
    end procedure;

    -----------------------------------------------------------------------
    -- Bit-bang capture a single UART byte from a line (simulates Docklight RX)
    -- Samples mid-bit, LSB first.
    -----------------------------------------------------------------------
    procedure uart_rx_byte(
        signal   line       : in  std_logic;
        constant bit_time   : in  time;
        variable data_out   : out std_logic_vector(7 downto 0)
    ) is
    begin
        wait until falling_edge(line);  -- start bit edge
        wait for bit_time / 2;          -- move to center of start bit
        for i in 0 to 7 loop
            wait for bit_time;
            data_out(i) := line;
        end loop;
        wait for bit_time;              -- land in the stop bit
        assert line = '1'
            report "uart_rx_byte: stop bit not '1' - framing error in capture"
            severity warning;
    end procedure;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- Unit Under Test
    uut : entity work.rs422_docklight_test
        generic map (
            CLK_FREQ       => CLK_FREQ,
            BAUD_RATE      => BAUD_RATE,
            NUM_BYTES      => NUM_BYTES,
            TIMEOUT_MS     => TIMEOUT_MS,
            BOOT_DELAY_MS  => BOOT_DELAY_MS,
            LED_STRETCH_MS => LED_STRETCH_MS
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            rs422_tx  => rs422_tx,
            rs422_rx  => rs422_rx,
            rs422_en  => rs422_en,
            rs422_nen => rs422_nen,
            led_ok    => led_ok,
            led_err   => led_err
        );

    -- Enable lines should be permanently tied active. Delay the first check
    -- by a couple of ns so we don't compare against the pre-elaboration 'U'
    -- default before the DUT's concurrent tie-off assignment first settles.
    check_enables : process
    begin
        wait for 2 ns;
        loop
            assert rs422_en = '1'
                report "rs422_en dropped low - should be permanently enabled" severity error;
            assert rs422_nen = '0'
                report "rs422_nen went high - should be permanently enabled (active-low)" severity error;
            wait on rs422_en, rs422_nen;
        end loop;
    end process;

    -- Simulation watchdog: fail out instead of hanging forever if something's wrong
    watchdog : process
    begin
        wait for 50 ms;
        report "WATCHDOG TIMEOUT: simulation did not complete in time" severity failure;
    end process;

    -----------------------------------------------------------------------
    -- Free-running "PC receive": always listening on rs422_tx, completely
    -- independent of whatever stim_proc is doing on the transmit side.
    -----------------------------------------------------------------------
    capture_proc : process
        variable b : std_logic_vector(7 downto 0);
    begin
        loop
            uart_rx_byte(rs422_tx, BIT_PERIOD, b);
            captured_bytes(captured_count) <= b;
            captured_count <= captured_count + 1;
        end loop;
    end process;

    -----------------------------------------------------------------------
    -- Main stimulus process (drives the "PC transmit" side + orchestrates
    -- the test sequence / checks against what capture_proc has collected)
    -----------------------------------------------------------------------
    stim_proc : process
        variable base      : natural;
        variable all_match : boolean;
    begin
        -- === INITIALIZATION ===
        rst_n    <= '0';
        rs422_rx <= '1';
        wait for 200 ns;
        rst_n <= '1';
        wait for 200 ns;
        wait until rising_edge(clk);

        ---------------------------------------------------------------
        -- TEST 0: Boot-up message, sent unprompted BOOT_DELAY_MS after
        -- reset release. Must complete before the DUT's FSM reaches
        -- echo-IDLE, so this has to be waited out before sending anything
        -- from the "PC" side (same "only listens while idle" limitation
        -- as the echo path - see file header note).
        ---------------------------------------------------------------
        report "--- STARTING TEST 0: waiting for unprompted boot message ---";
        base := captured_count; -- should be 0

        wait until captured_count = base + NUM_BYTES for (BOOT_DELAY_MS + 3) * 1 ms;

        all_match := (captured_count = base + NUM_BYTES);
        if not all_match then
            report "-> TEST 0 FAILED: boot message never arrived within " &
                   integer'image(BOOT_DELAY_MS + 3) & " ms." severity error;
        else
            for i in 0 to NUM_BYTES - 1 loop
                if captured_bytes(base + i) /= BOOT_MSG(i) then
                    all_match := false;
                    report "-> TEST 0: boot byte " & integer'image(i) & " mismatch - expected " &
                           to_hstring(BOOT_MSG(i)) & ", got " & to_hstring(captured_bytes(base + i))
                           severity error;
                end if;
            end loop;
        end if;

        if all_match then
            report "-> TEST 0 PASSED: boot message (11 22 33 44 55 66 77 88) received correctly.";
        else
            report "-> TEST 0 FAILED: see mismatch(es) above." severity error;
        end if;

        wait for 10 us; -- let the DUT settle into echo-IDLE before Test 1 starts

        ---------------------------------------------------------------
        -- TEST 1: Full 8-byte round trip
        ---------------------------------------------------------------
        report "--- STARTING TEST 1: Docklight sends 8 bytes, expects identical echo ---";
        base := captured_count;

        for i in 0 to NUM_BYTES - 1 loop
            uart_tx_byte(rs422_rx, TEST1_PAYLOAD(i), BIT_PERIOD);
        end loop;

        -- capture_proc runs concurrently and independently; just wait for it
        -- to collect the full echoed frame (generous margin over one frame time)
        wait until captured_count = base + NUM_BYTES for 12 * NUM_BYTES * BIT_PERIOD;

        all_match := (captured_count = base + NUM_BYTES);
        if not all_match then
            report "-> TEST 1 FAILED: echo frame never fully arrived (timed out)." severity error;
        else
            for i in 0 to NUM_BYTES - 1 loop
                if captured_bytes(base + i) /= TEST1_PAYLOAD(i) then
                    all_match := false;
                    report "-> TEST 1: byte " & integer'image(i) & " mismatch - sent " &
                           to_hstring(TEST1_PAYLOAD(i)) & ", echoed " & to_hstring(captured_bytes(base + i))
                           severity error;
                end if;
            end loop;
        end if;

        if all_match then
            report "-> TEST 1 PASSED: 8-byte frame echoed back identically.";
        else
            report "-> TEST 1 FAILED: see mismatch(es) above." severity error;
        end if;

        -- led_ok should pulse (active-low) shortly after the echo finishes
        wait until led_ok = '0' for 5 * BIT_PERIOD;
        if led_ok = '0' then
            report "-> TEST 1: led_ok correctly asserted after round trip.";
        else
            report "-> TEST 1 FAILED: led_ok never asserted after successful round trip." severity error;
        end if;
        wait until led_ok = '1'; -- let the stretch pulse finish before moving on

        wait for 10 us;

        ---------------------------------------------------------------
        -- TEST 2: Mid-frame silence -> inter-byte timeout recovery
        ---------------------------------------------------------------
        report "--- STARTING TEST 2: Docklight sends 3 of 8 bytes then goes silent ---";
        base := captured_count;

        for i in 0 to 2 loop
            uart_tx_byte(rs422_rx, TEST2_PAYLOAD(i), BIT_PERIOD);
        end loop;

        report "3 bytes sent, PC gone silent. Waiting >" & integer'image(TIMEOUT_MS) &
               "ms for led_err to latch...";

        rs422_rx <= '1'; -- line idles high, as if the PC simply stopped transmitting

        wait until led_err = '0' for (TIMEOUT_MS + 1) * 1 ms;

        if led_err = '0' then
            report "-> TEST 2 PASSED: led_err latched after inter-byte timeout.";
        else
            report "-> TEST 2 FAILED: led_err never latched." severity error;
        end if;

        assert captured_count = base
            report "-> TEST 2 FAILED: an echo was sent for an incomplete frame (should not happen)."
            severity error;

        ---------------------------------------------------------------
        -- TEST 3: Confirm the module recovers - a clean frame after the
        -- timeout should clear led_err and echo normally again.
        ---------------------------------------------------------------
        report "--- STARTING TEST 3: Clean frame after timeout should clear led_err ---";
        base := captured_count;

        for i in 0 to NUM_BYTES - 1 loop
            uart_tx_byte(rs422_rx, TEST1_PAYLOAD(i), BIT_PERIOD);
        end loop;

        wait until captured_count = base + NUM_BYTES for 12 * NUM_BYTES * BIT_PERIOD;

        all_match := (captured_count = base + NUM_BYTES);
        if all_match then
            for i in 0 to NUM_BYTES - 1 loop
                if captured_bytes(base + i) /= TEST1_PAYLOAD(i) then
                    all_match := false;
                    report "-> TEST 3: byte " & integer'image(i) & " mismatch on recovery frame" severity error;
                end if;
            end loop;
        else
            report "-> TEST 3 FAILED: recovery echo frame never fully arrived." severity error;
        end if;

        if all_match then
            report "-> TEST 3: recovery frame echoed back identically.";
        end if;

        wait until led_err = '1' for 5 * BIT_PERIOD;
        if led_err = '1' then
            report "-> TEST 3 PASSED: led_err cleared after a clean round trip.";
        else
            report "-> TEST 3 FAILED: led_err still latched after recovery frame." severity error;
        end if;

        -- === END OF SIMULATION ===
        report "--- ALL TESTS COMPLETED ---";
        wait for 10 us;
        std.env.stop; -- VHDL-2008
        wait;
    end process;

end architecture sim;