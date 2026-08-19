-- Simple 8N1 UART receiver.  The input is sampled at the configured baud rate.
library ieee;
use ieee.std_logic_1164.all;

entity uart_rx_8n1 is
  generic (
    CLK_HZ : positive := 50_000_000;
    BAUD   : positive := 115_200
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    rx         : in  std_logic;
    data_out   : out std_logic_vector(7 downto 0);
    data_valid : out std_logic
  );
end entity;

architecture rtl of uart_rx_8n1 is
  constant CLKS_PER_BIT : positive := CLK_HZ / BAUD;
  constant HALF_BIT     : positive := CLKS_PER_BIT / 2;

  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal state      : state_t := IDLE;
  signal count      : integer range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_index  : integer range 0 to 7 := 0;
  signal shift_reg  : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_meta    : std_logic := '1';
  signal rx_sync    : std_logic := '1';
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '0' then
        state      <= IDLE;
        count      <= 0;
        bit_index  <= 0;
        shift_reg  <= (others => '0');
        data_out   <= (others => '0');
        data_valid <= '0';
        rx_meta    <= '1';
        rx_sync    <= '1';
      else
        rx_meta    <= rx;
        rx_sync    <= rx_meta;
        data_valid <= '0';

        case state is
          when IDLE =>
            if rx_sync = '0' then
              count <= HALF_BIT - 1;
              state <= START_BIT;
            end if;

          when START_BIT =>
            if count = 0 then
              if rx_sync = '0' then
                count     <= CLKS_PER_BIT - 1;
                bit_index <= 0;
                state     <= DATA_BITS;
              else
                state <= IDLE;
              end if;
            else
              count <= count - 1;
            end if;

          when DATA_BITS =>
            if count = 0 then
              shift_reg(bit_index) <= rx_sync;
              count <= CLKS_PER_BIT - 1;
              if bit_index = 7 then
                state <= STOP_BIT;
              else
                bit_index <= bit_index + 1;
              end if;
            else
              count <= count - 1;
            end if;

          when STOP_BIT =>
            if count = 0 then
              if rx_sync = '1' then
                data_out   <= shift_reg;
                data_valid <= '1';
              end if;
              state <= IDLE;
            else
              count <= count - 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
