-- Simple 8N1 UART transmitter.
library ieee;
use ieee.std_logic_1164.all;

entity uart_tx_8n1 is
  generic (
    CLK_HZ : positive := 50_000_000;
    BAUD   : positive := 115_200
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    start      : in  std_logic;
    data_in    : in  std_logic_vector(7 downto 0);
    tx         : out std_logic;
    busy       : out std_logic
  );
end entity;

architecture rtl of uart_tx_8n1 is
  constant CLKS_PER_BIT : positive := CLK_HZ / BAUD;
  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal state     : state_t := IDLE;
  signal count     : integer range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_index : integer range 0 to 7 := 0;
  signal data_reg  : std_logic_vector(7 downto 0) := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '0' then
        state     <= IDLE;
        count     <= 0;
        bit_index <= 0;
        data_reg  <= (others => '0');
        tx        <= '1';
        busy      <= '0';
      else
        case state is
          when IDLE =>
            tx   <= '1';
            busy <= '0';
            if start = '1' then
              data_reg  <= data_in;
              count     <= CLKS_PER_BIT - 1;
              tx        <= '0';
              busy      <= '1';
              state     <= START_BIT;
            end if;

          when START_BIT =>
            if count = 0 then
              count     <= CLKS_PER_BIT - 1;
              bit_index <= 0;
              tx        <= data_reg(0);
              state     <= DATA_BITS;
            else
              count <= count - 1;
            end if;

          when DATA_BITS =>
            if count = 0 then
              count <= CLKS_PER_BIT - 1;
              if bit_index = 7 then
                tx    <= '1';
                state <= STOP_BIT;
              else
                bit_index <= bit_index + 1;
                tx        <= data_reg(bit_index + 1);
              end if;
            else
              count <= count - 1;
            end if;

          when STOP_BIT =>
            if count = 0 then
              tx    <= '1';
              busy  <= '0';
              state <= IDLE;
            else
              count <= count - 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
