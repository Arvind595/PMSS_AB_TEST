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
--   - Idles until a full 8-byte frame is received from Docklite.
--   - Echoes the exact same 8 bytes back out immediately after.
--   - led_ok   : stretched pulse (visible to the eye) each time a full
--                receive+echo round trip completes successfully.
--   - led_err  : latches on if the packet controller reports an inter-byte
--                timeout (rx_timeout_err), clears on the next successful
--                round trip.
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

    -- Echo FSM
    type echo_state_t is (IDLE, SEND, WAIT_DONE);
    signal echo_state : echo_state_t := IDLE;

    -- LED stretcher / latch
    constant LED_STRETCH_CYCLES : integer := (CLK_FREQ / 1000) * LED_STRETCH_MS;
    signal   led_ok_cnt         : integer range 0 to LED_STRETCH_CYCLES := 0;
    signal   led_err_latched    : std_logic := '0';

begin

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
    -- Echo FSM: on a fully received frame, latch it and send it straight
    -- back out. See "Known assumption" note at the top of this file.
    -----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                echo_state   <= IDLE;
                tx_start_sig <= '0';
                tx_data_sig  <= (others => (others => '0'));
            else
                tx_start_sig <= '0'; -- default: single-cycle pulse only

                case echo_state is
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
