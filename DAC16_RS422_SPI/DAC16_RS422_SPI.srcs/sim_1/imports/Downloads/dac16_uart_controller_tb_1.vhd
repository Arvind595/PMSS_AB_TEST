--------------------------------------------------------------------------------
-- dac16_uart_controller_tb.vhd
--
-- The DAC code is sent directly in Byte3 (MSB)/Byte4 (LSB) of the command
-- packet - no voltage-to-code conversion happens in the FPGA, so expected
-- codes below are just the same values sent, not derived from a formula.
--
-- Self-checking testbench for dac16_uart_controller. Acts as the remote UART
-- host (Docklite stand-in): bit-bangs 8-byte command packets onto RS422_RX,
-- decodes the echoed reply from RS422_TX, and independently sniffs each
-- channel's SPI bus (nCS/SCLK/SDIO0) to confirm the actual DAC write matches
-- the expected code for the commanded voltage.
--
-- The UART reply decoder runs as a persistent, always-listening process
-- (like the per-channel SPI monitors) rather than as blocking code invoked
-- right after the send completes. That matters: the DUT can start its reply
-- a few hundred ns before the sender's final stop-bit wait finishes, so a
-- "send fully, then start listening" receiver can begin mid-frame, lose
-- alignment, and run off the end of the transmission waiting for a start
-- bit that will never come. A monitor that has been listening since time 0
-- never has that problem.
--
-- Requires VHDL-2008 (to_hstring, integer'image) - same note as the other
-- testbenches in this project: set this file's "File Type" to VHDL 2008 in
-- Vivado if your project defaults to an older language version.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.rs422_pkg.all;

entity dac16_uart_controller_tb is
end entity dac16_uart_controller_tb;

architecture behavior of dac16_uart_controller_tb is

    constant CLK_PERIOD   : time    := 20 ns; -- 50 MHz
    constant CLK_FREQ     : integer := 50_000_000;
    constant BAUD_RATE    : integer := 115200;
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;      -- 434 (matches DUT's truncation)
    constant BIT_PERIOD   : time    := CLKS_PER_BIT * CLK_PERIOD; -- 8680 ns

    signal RST_SW         : std_logic := '0';
    signal FPGA_CLK_50MHZ : std_logic := '0';
    signal RS422_TX       : std_logic;
    signal RS422_RX       : std_logic := '1'; -- UART idle = high

    signal DAC_nRST  : std_logic_vector(15 downto 0);
    signal DAC_nLOAD : std_logic_vector(15 downto 0);
    signal DAC_nCS   : std_logic_vector(15 downto 0);
    signal DAC_SCLK  : std_logic_vector(15 downto 0);
    signal DAC_SDIO0 : std_logic_vector(15 downto 0);
    signal DAC_SDIO2 : std_logic_vector(15 downto 0);
    signal DAC_SDIO3 : std_logic_vector(15 downto 0);

    signal STS1_LED_GREEN : std_logic;
    signal TP_CLK_TST     : std_logic;

    -- Per-channel SPI-frame capture (persistent monitors, one per channel)
    type word_arr_t is array (0 to 15) of std_logic_vector(23 downto 0);
    type int_arr_t  is array (0 to 15) of integer;
    signal cap_word : word_arr_t := (others => (others => '0'));
    signal cap_bits : int_arr_t  := (others => 0);
    signal cap_seq  : int_arr_t  := (others => 0);

    -- Persistent UART reply capture
    signal reply_bytes : byte_array_t(0 to 7) := (others => (others => '0'));
    signal reply_seq   : integer := 0;

    ----------------------------------------------------------------------------
    -- UART bit-bang helpers (architecture-level so both the stimulus process
    -- and the persistent reply monitor can use them)
    ----------------------------------------------------------------------------
    procedure uart_send_byte(signal line_sig : out std_logic; data : std_logic_vector(7 downto 0)) is
    begin
        line_sig <= '0';               -- start bit
        wait for BIT_PERIOD;
        for i in 0 to 7 loop
            line_sig <= data(i);       -- LSB first
            wait for BIT_PERIOD;
        end loop;
        line_sig <= '1';               -- stop bit
        wait for BIT_PERIOD;
    end procedure;

    procedure uart_send_packet(signal line_sig : out std_logic; pkt : byte_array_t(0 to 7)) is
    begin
        for b in 0 to 7 loop
            uart_send_byte(line_sig, pkt(b));
        end loop;
    end procedure;

    procedure uart_recv_byte(signal line_sig : in std_logic; variable data : out std_logic_vector(7 downto 0)) is
    begin
        wait until line_sig = '0';          -- start bit begins
        wait for BIT_PERIOD + BIT_PERIOD/2; -- align to middle of data bit 0
        for i in 0 to 7 loop
            data(i) := line_sig;
            wait for BIT_PERIOD;
        end loop;
    end procedure;

    procedure uart_recv_packet(signal line_sig : in std_logic; variable pkt : out byte_array_t(0 to 7)) is
        variable b : std_logic_vector(7 downto 0);
    begin
        for i in 0 to 7 loop
            uart_recv_byte(line_sig, b);
            pkt(i) := b;
        end loop;
    end procedure;

begin

    ----------------------------------------------------------------------------
    -- UUT
    ----------------------------------------------------------------------------
    uut: entity work.dac16_uart_controller
        generic map (
            SIM_MODE  => true,
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            RST_SW         => RST_SW,
            FPGA_CLK_50MHZ => FPGA_CLK_50MHZ,
            RS422_TX       => RS422_TX,
            RS422_RX       => RS422_RX,
            DAC_nRST       => DAC_nRST,
            DAC_nLOAD      => DAC_nLOAD,
            DAC_nCS        => DAC_nCS,
            DAC_SCLK       => DAC_SCLK,
            DAC_SDIO0      => DAC_SDIO0,
            DAC_SDIO2      => DAC_SDIO2,
            DAC_SDIO3      => DAC_SDIO3,
            STS1_LED_GREEN => STS1_LED_GREEN,
            TP_CLK_TST     => TP_CLK_TST
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
    -- Persistent UART reply monitor - always listening on RS422_TX since t=0,
    -- so it can never start mid-frame.
    ----------------------------------------------------------------------------
    uart_reply_monitor : process
        variable pkt : byte_array_t(0 to 7);
    begin
        loop
            uart_recv_packet(RS422_TX, pkt);
            reply_bytes <= pkt;
            reply_seq   <= reply_seq + 1;
        end loop;
    end process;

    ----------------------------------------------------------------------------
    -- Persistent per-channel SPI monitors: continuously capture every frame
    -- that appears on each channel's nCS/SCLK/SDIO0, so the main stimulus
    -- process can check "what was the last thing written to channel N".
    ----------------------------------------------------------------------------
    gen_monitors : for i in 0 to 15 generate

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
            variable w : std_logic_vector(23 downto 0);
            variable n : integer;
        begin
            loop
                capture_frame(DAC_nCS(i), DAC_SCLK(i), DAC_SDIO0(i), w, n);
                cap_word(i) <= w;
                cap_bits(i) <= n;
                cap_seq(i)  <= cap_seq(i) + 1;
            end loop;
        end process;

    end generate gen_monitors;

    ----------------------------------------------------------------------------
    -- Stimulus / checker
    ----------------------------------------------------------------------------
    stim_proc : process
        variable fail_count : integer := 0;

        procedure check(cond : boolean; msg : string; fail_cnt : inout integer) is
        begin
            if cond then
                report "PASS: " & msg severity note;
            else
                report "FAIL: " & msg severity error;
                fail_cnt := fail_cnt + 1;
            end if;
        end procedure;

        -- Sends one command packet, captures the echoed reply, and (for
        -- channels expected to receive a write) checks the resulting SPI
        -- frame. exp_write = false skips the SPI check entirely (used for
        -- the error-path tests where no write should occur).
        procedure run_case(
            name        : string;
            pkt         : byte_array_t(0 to 7);
            exp_reply   : byte_array_t(0 to 7);
            exp_write   : boolean;
            ch          : integer;
            exp_code    : std_logic_vector(15 downto 0);
            fail_cnt    : inout integer
        ) is
            variable reply_seq_pre : integer;
            variable spi_seq_pre   : integer;
            variable w             : std_logic_vector(23 downto 0);
            variable n             : integer;
        begin
            reply_seq_pre := reply_seq;
            if exp_write then
                spi_seq_pre := cap_seq(ch);
            end if;

            uart_send_packet(RS422_RX, pkt);

            if reply_seq = reply_seq_pre then
                wait until reply_seq /= reply_seq_pre;
            end if;
            check(reply_bytes = exp_reply,
                  name & ": echo/reply bytes correct",
                  fail_cnt);

            if exp_write then
                if cap_seq(ch) = spi_seq_pre then
                    wait until cap_seq(ch) /= spi_seq_pre;
                end if;
                w := cap_word(ch);
                n := cap_bits(ch);
                check(n = 24,
                      name & ": SPI frame bit count = 24",
                      fail_cnt);
                check(w = (x"2A" & exp_code),
                      name & ": SPI frame = 0x" & to_hstring(w)
                             & ", expected 0x" & to_hstring(x"2A" & exp_code),
                      fail_cnt);
            else
                -- No write expected: give it a generous window; the
                -- caller's own cap_seq check (below) confirms nothing new
                -- appeared on the target channel.
                wait for 20 us;
            end if;
        end procedure;

        variable p          : byte_array_t(0 to 7);
        variable r          : byte_array_t(0 to 7);
        variable seq_before : integer;

    begin
        RST_SW   <= '0';
        RS422_RX <= '1';
        wait for 200 ns;
        RST_SW <= '1';

        -- Let all 16 channels finish their power-on sequence (SIM_MODE
        -- shortens this to ~120us) before sending any UART commands, so
        -- every SPI transaction we observe afterward is unambiguously the
        -- result of that specific command.
        wait for 200 us;

        ------------------------------------------------------------------
        -- Test 1: valid write, CH3, code 0xBDA9 5V sent directly 
        ------------------------------------------------------------------
        p := (x"55", x"01", x"03", x"BD", x"A9", x"00", x"00", x"00");
        run_case("T1 CH3 code 0xBDA9", p, p, true, 3, x"BDA9", fail_count);

        ------------------------------------------------------------------
        -- Test 2: valid write, CH7, code 0x425C -5V sent directly
        ------------------------------------------------------------------
        p := (x"55", x"01", x"07", x"42", x"5C", x"00", x"00", x"00");
        run_case("T2 CH7 code 0x425C", p, p, true, 7, x"425C", fail_count);

        ------------------------------------------------------------------
        -- Test 3: invalid command byte (0x02, not 0x01), CH5
        -- expect: reply byte1 = 0xFF, everything else echoed, no SPI write
        ------------------------------------------------------------------
        p := (x"55", x"02", x"05", x"12", x"34", x"00", x"00", x"00");
        r := p; r(1) := x"FF";
        seq_before := cap_seq(5);
        run_case("T3 bad cmd byte CH5", p, r, false, 5, x"0000", fail_count);
        check(cap_seq(5) = seq_before, "T3: no SPI write occurred on CH5", fail_count);

        ------------------------------------------------------------------
        -- Test 4: invalid sync byte (0xAA, not 0x55), CH2
        -- expect: byte0 echoed as received (0xAA), byte1 = 0xFF, rest as sent
        ------------------------------------------------------------------
        p := (x"AA", x"01", x"02", x"AB", x"CD", x"00", x"00", x"00");
        r := p; r(1) := x"FF";
        seq_before := cap_seq(2);
        run_case("T4 bad sync byte CH2", p, r, false, 2, x"0000", fail_count);
        check(cap_seq(2) = seq_before, "T4: no SPI write occurred on CH2", fail_count);

        ------------------------------------------------------------------
        -- Test 5: channel out of range (20, valid range is 0-15)
        -- expect: byte1 = 0xFF, byte2 (=20) echoed as-is, rest as sent
        ------------------------------------------------------------------
        p := (x"55", x"01", x"14", x"55", x"55", x"00", x"00", x"00"); -- 0x14 = 20
        r := p; r(1) := x"FF";
        run_case("T5 out-of-range channel", p, r, false, 0, x"0000", fail_count);

        ------------------------------------------------------------------
        -- Test 6: minimum code boundary, CH10, code 0x0000
        -- any 16-bit code is valid now (no conversion/clamping happens in
        -- the FPGA), so this just confirms the extremes pass through intact
        ------------------------------------------------------------------
        p := (x"55", x"01", x"0A", x"00", x"00", x"00", x"00", x"00");
        run_case("T6 CH10 code 0x0000", p, p, true, 10, x"0000", fail_count);

        ------------------------------------------------------------------
        -- Test 7: maximum code boundary, CH12, code 0xFFFF
        ------------------------------------------------------------------
        p := (x"55", x"01", x"0C", x"FF", x"FF", x"00", x"00", x"00");
        run_case("T7 CH12 code 0xFFFF", p, p, true, 12, x"FFFF", fail_count);

        report "--------------------------------------------------------------";
        if fail_count = 0 then
            report "TESTBENCH RESULT: ALL TESTS PASSED" severity note;
        else
            report "TESTBENCH RESULT: FAIL - " & integer'image(fail_count) & " check(s) failed"
                severity error;
        end if;
        report "--------------------------------------------------------------";

        std.env.stop;
    end process;

end architecture behavior;