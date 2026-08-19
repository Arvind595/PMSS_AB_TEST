-- Classic-SPI Mode-0 master for one AD3551R.
-- One-byte and 16-bit writes are supported.  Reads return one byte.
library ieee;
use ieee.std_logic_1164.all;

entity ad3551r_spi_master is
  generic (
    CLK_HZ : positive := 50_000_000;
    SPI_HZ : positive := 5_000_000
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    start        : in  std_logic;
    read_not_write : in std_logic;
    word_access  : in  std_logic; -- '1': 16-bit data, '0': one byte
    address      : in  std_logic_vector(6 downto 0);
    write_data   : in  std_logic_vector(15 downto 0);
    busy         : out std_logic;
    done         : out std_logic;
    read_data    : out std_logic_vector(7 downto 0);
    dac_ncs      : out std_logic;
    dac_sclk     : out std_logic;
    dac_sdio0    : out std_logic;
    dac_sdio1    : in  std_logic
  );
end entity;

architecture rtl of ad3551r_spi_master is
  constant HALF_PERIOD_TICKS : positive := CLK_HZ / (2 * SPI_HZ);
  type state_t is (IDLE, WAIT_RISE, WAIT_FALL, WAIT_FINISH);
  signal state        : state_t := IDLE;
  signal tick_count   : integer range 0 to HALF_PERIOD_TICKS - 1 := 0;
  signal bit_position : integer range 0 to 23 := 0;
  signal tx_frame     : std_logic_vector(23 downto 0) := (others => '0');
  signal rx_frame     : std_logic_vector(7 downto 0) := (others => '0');
  signal read_active  : std_logic := '0';
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '0' then
        state        <= IDLE;
        tick_count   <= 0;
        bit_position <= 0;
        tx_frame     <= (others => '0');
        rx_frame     <= (others => '0');
        read_active  <= '0';
        busy         <= '0';
        done         <= '0';
        read_data    <= (others => '0');
        dac_ncs      <= '1';
        dac_sclk     <= '0';
        dac_sdio0    <= '0';
      else
        done <= '0';

        case state is
          when IDLE =>
            busy      <= '0';
            dac_ncs   <= '1';
            dac_sclk  <= '0';
            dac_sdio0 <= '0';
            if start = '1' then
              busy        <= '1';
              dac_ncs     <= '0';
              tick_count  <= HALF_PERIOD_TICKS - 1;
              read_active <= read_not_write;
              rx_frame    <= (others => '0');

              if word_access = '1' then
                tx_frame     <= '0' & address & write_data;
                bit_position <= 23;
                dac_sdio0    <= '0'; -- R/W=0, first bit is driven before SCLK rises.
              elsif read_not_write = '1' then
                tx_frame(23 downto 16) <= (others => '0');
                tx_frame(15 downto 8)  <= '1' & address;
                tx_frame(7 downto 0)   <= (others => '0');
                bit_position <= 15;
                dac_sdio0    <= '1'; -- R/W=1, first bit is driven before SCLK rises.
              else
                tx_frame(23 downto 16) <= (others => '0');
                tx_frame(15 downto 8)  <= '0' & address;
                tx_frame(7 downto 0)   <= write_data(7 downto 0);
                bit_position <= 15;
                dac_sdio0    <= '0'; -- R/W=0, first bit is driven before SCLK rises.
              end if;
              state <= WAIT_RISE;
            end if;

          when WAIT_RISE =>
            if tick_count = 0 then
              dac_sclk <= '1';
              if (read_active = '1') and (bit_position < 8) then
                rx_frame(bit_position) <= dac_sdio1;
              end if;

              tick_count <= HALF_PERIOD_TICKS - 1;
              if bit_position = 0 then
                state <= WAIT_FINISH;
              else
                state <= WAIT_FALL;
              end if;
            else
              tick_count <= tick_count - 1;
            end if;

          when WAIT_FALL =>
            if tick_count = 0 then
              dac_sclk     <= '0';
              bit_position <= bit_position - 1;
              dac_sdio0    <= tx_frame(bit_position - 1);
              tick_count   <= HALF_PERIOD_TICKS - 1;
              state        <= WAIT_RISE;
            else
              tick_count <= tick_count - 1;
            end if;

          when WAIT_FINISH =>
            if tick_count = 0 then
              dac_sclk  <= '0';
              dac_ncs   <= '1';
              dac_sdio0 <= '0';
              busy      <= '0';
              done      <= '1';
              read_data <= rx_frame;
              state     <= IDLE;
            else
              tick_count <= tick_count - 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
