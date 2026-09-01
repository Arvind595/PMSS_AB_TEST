-------------------------------------------------------------------------------
-- rs422_docklight_test
--
-- Hardware application (NOT a testbench) that exercises the RS422 packet
-- stack end-to-end against Docklite (host PC software) over a real physical
-- RS422/UART link:
--
--   Docklite (PC) --8 bytes--> rs422_rx --> rs422_packet_controller -->
--       app latches the 8 received bytes --> echoes them back out -->
--       rs422_tx --8 bytes--> Docklite (PC), for the PC side to verify.
--
-- Behaviour:
--   - On power-up/reset release, waits BOOT_DELAY_MS (default 10 ms) and
--     then sends one fixed 8-byte boot message (11 22 33 44 55 66 77 88)
--     out to Docklite, unprompted - lets the PC side confirm the link is
--     alive before any echo traffic happens.
--   - After the boot message finishes sending, drops into normal echo mode:
--     idles until a full 8-byte frame is received from Docklite, then
--     echoes the exact same 8 bytes back out immediately.
--   - led_ok   : stretched pulse (visible to the eye) each time a full
--                transmit completes successfully - this includes the boot
--                message itself as well as every echo round trip, since
--                both go through the same tx_done_pkt pulse.
--   - led_err  : latches on if the packet controller reports an inter-byte
--                timeout (rx_timeout_err), clears on the next successful
--                round trip.
--
-- Note: BOOT_MSG below is a fixed 8-byte constant sized to match the
-- default NUM_BYTES = 8. If NUM_BYTES is changed via the generic, BOOT_MSG
-- must be resized/repopulated to match, or the aggregate assignment won't
-- compile.
--
-- Known assumption (ping-pong protocol):
--   This app only watches for a new frame while it is IDLE. If Docklite
--   sends a second 8-byte frame before the echo of the first has finished
--   transmitting, that second frame's rx_valid pulse is not captured here
--   and its bytes are dropped at this layer (the packet controller's RX
--   engine still runs independently and will resynchronize on the next
--   frame). This is fine for a typical "send 8 bytes, wait for the echo,
--   then send the next 8 bytes" Docklite test flow. If Docklite streams
--   frames back-to-back without waiting, tell me and I'll add a small
--   elastic buffer (e.g. a 2-deep FIFO) in front of the echo FSM.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rs422_pkg.all;

entity rs422_docklight_test is
    generic (
        CLK_FREQ       : integer := 50_000_000; -- FPGA clock feeding this module (post-PLL/MMCM if used)
        BAUD_RATE      : integer := 115200;     -- Must match Docklite's configured baud rate
        NUM_BYTES      : integer := 8;
        TIMEOUT_MS     : integer := 5;          -- Inter-byte stall threshold, forwarded to packet controller
        BOOT_DELAY_MS  : integer := 10;         -- Delay after reset release before sending the boot message
        LED_STRETCH_MS : integer := 1000          -- How long led_ok stays lit per successful round trip
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic; -- Board reset, ACTIVE LOW (matches rs422_packet_controller's rst polarity).
                                   -- If your board's reset button/switch is active-high, invert it before
                                   -- connecting here (rst_n <= not board_reset_button).

        -- Physical RS422 pins to the transceiver
        rs422_tx : out std_logic;
        rs422_rx : in  std_logic;
		rs422_en : out std_logic;
		rs422_nen: out std_logic;

        -- Status LEDs
        led_ok   : out std_logic; -- Pulses on each successful 8-byte receive+echo
        led_err  : out std_logic  -- Latches on inter-byte timeout / dropped frame
    );
end entity rs422_docklight_test;

architecture rtl of rs422_docklight_test is

    -- Packet controller <-> app signals
    signal rx_data_pkt    : byte_array_t(0 to NUM_BYTES-1);
    signal rx_valid_pkt   : std_logic;
    signal rx_timeout_pkt : std_logic;

    signal tx_start_sig   : std_logic := '0';
    signal tx_data_sig    : byte_array_t(0 to NUM_BYTES-1) := (others => (others => '0'));
    signal tx_busy_pkt    : std_logic;
    signal tx_done_pkt    : std_logic;

    -- Echo FSM (starts in BOOT_WAIT on power-up; drops into normal IDLE
    -- echo mode once the boot message has been sent)
    type echo_state_t is (BOOT_WAIT, BOOT_SEND, BOOT_WAIT_DONE, IDLE, SEND, WAIT_DONE);
    signal echo_state : echo_state_t := BOOT_WAIT;

    -- Boot message: sent once, BOOT_DELAY_MS after reset release
    constant BOOT_MSG : byte_array_t(0 to NUM_BYTES-1) :=
        (x"11", x"22", x"33", x"44", x"55", x"66", x"77", x"88");
    constant BOOT_DELAY_CYCLES : integer := (CLK_FREQ / 1000) * BOOT_DELAY_MS;
    signal   boot_delay_cnt    : integer range 0 to BOOT_DELAY_CYCLES := 0;

    -- LED stretcher / latch
    constant LED_STRETCH_CYCLES : integer := (CLK_FREQ / 1000) * LED_STRETCH_MS;
    signal   led_ok_cnt         : integer range 0 to LED_STRETCH_CYCLES := 0;
    signal   led_err_latched    : std_logic := '0';

begin

    -----------------------------------------------------------------------
    -- RS422 transceiver enable lines: permanently enabled at the app level
    -- (this design always drives and always listens; no half-duplex
    -- direction switching needed). rs422_en is active-high, rs422_nen is
    -- active-low, so both '1'/'0' below mean "enabled".
    -----------------------------------------------------------------------
    rs422_en  <= '1';
    rs422_nen <= '0';

    -----------------------------------------------------------------------
    -- Packet controller instance
    -----------------------------------------------------------------------
    u_packet_ctrl : entity work.rs422_packet_controller
        generic map (
            CLK_FREQ   => CLK_FREQ,
            BAUD_RATE  => BAUD_RATE,
            NUM_BYTES  => NUM_BYTES,
            TIMEOUT_MS => TIMEOUT_MS
        )
        port map (
            clk               => clk,
            rst               => rst_n,   -- active-low, straight through

            rs422_tx          => rs422_tx,
            rs422_rx          => rs422_rx,

            tx_start          => tx_start_sig,
            tx_data           => tx_data_sig,
            tx_busy           => tx_busy_pkt,
            tx_done           => tx_done_pkt,

            rx_data           => rx_data_pkt,
            rx_valid          => rx_valid_pkt,
            rx_timeout_err    => rx_timeout_pkt,

            debug_rx_byte_cnt => open, -- hook up to an ILA later if you want per-byte visibility
            debug_tx_byte_cnt => open
        );

    -----------------------------------------------------------------------
    -- Boot + Echo FSM: on power-up, waits BOOT_DELAY_MS then sends the
    -- fixed boot message once; after that, on a fully received frame,
    -- latches it and sends it straight back out. See "Known assumption"
    -- note at the top of this file.
    -----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                echo_state    <= BOOT_WAIT;
                boot_delay_cnt <= 0;
                tx_start_sig  <= '0';
                tx_data_sig   <= (others => (others => '0'));
            else
                tx_start_sig <= '0'; -- default: single-cycle pulse only

                case echo_state is
                    when BOOT_WAIT =>
                        if boot_delay_cnt < BOOT_DELAY_CYCLES - 1 then
                            boot_delay_cnt <= boot_delay_cnt + 1;
                        else
                            tx_data_sig <= BOOT_MSG;
                            echo_state  <= BOOT_SEND;
                        end if;

                    when BOOT_SEND =>
                        if tx_busy_pkt = '0' then
                            tx_start_sig <= '1';
                            echo_state   <= BOOT_WAIT_DONE;
                        end if;

                    when BOOT_WAIT_DONE =>
                        if tx_done_pkt = '1' then
                            echo_state <= IDLE; -- boot message sent, now normal echo mode
                        end if;

                    when IDLE =>
                        if rx_valid_pkt = '1' then
                            tx_data_sig <= rx_data_pkt; -- latch the frame just received
                            echo_state  <= SEND;
                        end if;

                    when SEND =>
                        if tx_busy_pkt = '0' then
                            tx_start_sig <= '1';
                            echo_state   <= WAIT_DONE;
                        end if;

                    when WAIT_DONE =>
                        if tx_done_pkt = '1' then
                            echo_state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------
    -- led_ok: stretch the single-cycle tx_done pulse so it's visible.
    -- Lights for LED_STRETCH_MS every time a receive+echo round trip
    -- completes successfully.
    -----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                led_ok_cnt <= 0;
            elsif tx_done_pkt = '1' then
                led_ok_cnt <= LED_STRETCH_CYCLES;
            elsif led_ok_cnt > 0 then
                led_ok_cnt <= led_ok_cnt - 1;
            end if;
        end if;
    end process;
    led_ok <= '0' when led_ok_cnt > 0 else '1';

    -----------------------------------------------------------------------
    -- led_err: latch on any inter-byte timeout reported by the packet
    -- controller; clears the moment the next round trip completes cleanly.
    -----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                led_err_latched <= '0';
            elsif rx_timeout_pkt = '1' then
                led_err_latched <= '1';
            elsif tx_done_pkt = '1' then
                led_err_latched <= '0';
            end if;
        end if;
    end process;
    led_err <= not led_err_latched;

end architecture rtl;
