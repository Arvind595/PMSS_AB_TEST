-- One-AD3551R DC-output and register-readback test design.
-- Docklight, 115200 baud, 8 data bits, no parity, one stop bit:
--   Whhhh<CR>  write a 16-bit DAC code. Example: W8000<CR>
--   Raa<CR>    read one register byte.  Example: R0A<CR>
-- Replies:
--   OK<CR><LF>
--   Raa=vv<CR><LF>
--   ERR<CR><LF>
-- Use only DAC 0 for this test.  A vector wrapper can map these scalar
-- signals to index 0 of the final 16-DAC hardware interface.
library ieee;
use ieee.std_logic_1164.all;
use work.ad3551r_test_pkg.all;

entity ad3551r_dc_test_top is
  generic (
    CLK_HZ : positive := 50_000_000;
    UART_BAUD : positive := 115_200;
    SPI_HZ : positive := 5_000_000
  );
  port (
    clk_50mhz   : in  std_logic;
    rst         : in  std_logic; -- active-high FPGA reset

    rs422_rx    : in  std_logic; -- MAX14891 receiver logic output
    rs422_tx    : out std_logic; -- MAX3045 transmitter logic input

    dac_nalert  : in  std_logic;
    dac_nrst    : out std_logic;
    dac_nload   : out std_logic;
    dac_ncs     : out std_logic;
    dac_sclk    : out std_logic;
    dac_sdio0   : out std_logic;
    dac_sdio1   : in  std_logic;
    dac_sdio2   : inout std_logic;
    dac_sdio3   : inout std_logic;
    dac_mode_qspi : out std_logic;

    led_ready   : out std_logic;
    led_alert   : out std_logic
  );
end entity;

architecture rtl of ad3551r_dc_test_top is
  constant RESET_TICKS : positive := CLK_HZ / 10_000; -- 100 us

  constant REG_ERR_STATUS       : std_logic_vector(6 downto 0) := "0010111"; -- 0x17
  constant REG_SCRATCH_PAD      : std_logic_vector(6 downto 0) := "0001010"; -- 0x0A
  constant REG_CH0_OUTPUT_RANGE : std_logic_vector(6 downto 0) := "0011001"; -- 0x19
  constant REG_CH0_DAC_16B_MSB  : std_logic_vector(6 downto 0) := "0101010"; -- 0x2A, descending write also loads 0x29

  type boot_state_t is (
    BOOT_RESET, BOOT_CLEAR_ERR_START, BOOT_CLEAR_ERR_WAIT,
    BOOT_RANGE_START, BOOT_RANGE_WAIT,
    BOOT_SCRATCH_WR_START, BOOT_SCRATCH_WR_WAIT,
    BOOT_SCRATCH_RD_START, BOOT_SCRATCH_RD_WAIT,
    BOOT_ZERO_START, BOOT_ZERO_WAIT, BOOT_FAIL, READY,
    CMD_WRITE_START, CMD_WRITE_WAIT, CMD_READ_START, CMD_READ_WAIT,
    REPLY_LAUNCH, REPLY_WAIT_BUSY, REPLY_WAIT_DONE
  );
  signal boot_state : boot_state_t := BOOT_RESET;
  signal reset_count : integer range 0 to RESET_TICKS - 1 := 0;

  signal uart_rx_data  : byte_t;
  signal uart_rx_valid : std_logic;
  signal uart_tx_data  : byte_t := (others => '0');
  signal uart_tx_start : std_logic := '0';
  signal uart_tx_busy  : std_logic;

  signal spi_start     : std_logic := '0';
  signal spi_read      : std_logic := '0';
  signal spi_word      : std_logic := '0';
  signal spi_addr      : std_logic_vector(6 downto 0) := (others => '0');
  signal spi_wdata     : std_logic_vector(15 downto 0) := (others => '0');
  signal spi_done      : std_logic;
  signal spi_rdata     : byte_t;

  type parse_state_t is (P_IDLE, P_W3, P_W2, P_W1, P_W0, P_W_END,
                         P_R1, P_R0, P_R_END);
  signal parse_state : parse_state_t := P_IDLE;
  signal parsed_word : std_logic_vector(15 downto 0) := (others => '0');
  signal parsed_addr : byte_t := (others => '0');
  signal cmd_write_request : std_logic := '0';
  signal cmd_read_request  : std_logic := '0';
  signal cmd_error_request : std_logic := '0';

  signal command_word : std_logic_vector(15 downto 0) := (others => '0');
  signal command_addr : byte_t := (others => '0');
  signal reply_mem    : byte_array_t(0 to 15) := (others => (others => '0'));
  signal reply_length : integer range 1 to 16 := 1;
  signal reply_index  : integer range 0 to 15 := 0;
begin
  -- Classic SPI uses SDIO0 for input to the DAC and SDIO1 for output from it.
  -- These pins are not used in classic SPI mode.
  dac_sdio2 <= 'Z';
  dac_sdio3 <= 'Z';
  dac_mode_qspi <= '0';
  dac_nload <= '1'; -- Direct writes to CH0_DAC_16B do not require LDAC.
  led_alert <= not dac_nalert;
  led_ready <= '1' when boot_state = READY else '0';

  u_uart_rx : entity work.uart_rx_8n1
    generic map (CLK_HZ => CLK_HZ, BAUD => UART_BAUD)
    port map (
      clk => clk_50mhz, rst => rst, rx => rs422_rx,
      data_out => uart_rx_data, data_valid => uart_rx_valid
    );

  u_uart_tx : entity work.uart_tx_8n1
    generic map (CLK_HZ => CLK_HZ, BAUD => UART_BAUD)
    port map (
      clk => clk_50mhz, rst => rst, start => uart_tx_start,
      data_in => uart_tx_data, tx => rs422_tx, busy => uart_tx_busy
    );

  u_spi : entity work.ad3551r_spi_master
    generic map (CLK_HZ => CLK_HZ, SPI_HZ => SPI_HZ)
    port map (
      clk => clk_50mhz, rst => rst, start => spi_start,
      read_not_write => spi_read, word_access => spi_word,
      address => spi_addr, write_data => spi_wdata,
      busy => open, done => spi_done, read_data => spi_rdata,
      dac_ncs => dac_ncs, dac_sclk => dac_sclk,
      dac_sdio0 => dac_sdio0, dac_sdio1 => dac_sdio1
    );

  -- Docklight command parser.  Commands are accepted only after DAC startup.
  process (clk_50mhz)
  begin
    if rising_edge(clk_50mhz) then
      if rst = '1' then
        parse_state       <= P_IDLE;
        parsed_word       <= (others => '0');
        parsed_addr       <= (others => '0');
        cmd_write_request <= '0';
        cmd_read_request  <= '0';
        cmd_error_request <= '0';
      else
        cmd_write_request <= '0';
        cmd_read_request  <= '0';
        cmd_error_request <= '0';

        if (boot_state = READY) and (uart_rx_valid = '1') then
          case parse_state is
            when P_IDLE =>
              if uart_rx_data = x"57" then       -- W
                parse_state <= P_W3;
              elsif uart_rx_data = x"52" then    -- R
                parse_state <= P_R1;
              elsif uart_rx_data /= x"0A" then   -- ignore line-feed only
                cmd_error_request <= '1';
              end if;

            when P_W3 =>
              if is_hex_ascii(uart_rx_data) then
                parsed_word(15 downto 12) <= ascii_to_nibble(uart_rx_data);
                parse_state <= P_W2;
              else
                cmd_error_request <= '1'; parse_state <= P_IDLE;
              end if;
            when P_W2 =>
              if is_hex_ascii(uart_rx_data) then
                parsed_word(11 downto 8) <= ascii_to_nibble(uart_rx_data);
                parse_state <= P_W1;
              else
                cmd_error_request <= '1'; parse_state <= P_IDLE;
              end if;
            when P_W1 =>
              if is_hex_ascii(uart_rx_data) then
                parsed_word(7 downto 4) <= ascii_to_nibble(uart_rx_data);
                parse_state <= P_W0;
              else
                cmd_error_request <= '1'; parse_state <= P_IDLE;
              end if;
            when P_W0 =>
              if is_hex_ascii(uart_rx_data) then
                parsed_word(3 downto 0) <= ascii_to_nibble(uart_rx_data);
                parse_state <= P_W_END;
              else
                cmd_error_request <= '1'; parse_state <= P_IDLE;
              end if;
            when P_W_END =>
              if uart_rx_data = x"0D" then
                cmd_write_request <= '1';
              else
                cmd_error_request <= '1';
              end if;
              parse_state <= P_IDLE;

            when P_R1 =>
              if is_hex_ascii(uart_rx_data) then
                parsed_addr(7 downto 4) <= ascii_to_nibble(uart_rx_data);
                parse_state <= P_R0;
              else
                cmd_error_request <= '1'; parse_state <= P_IDLE;
              end if;
            when P_R0 =>
              if is_hex_ascii(uart_rx_data) then
                parsed_addr(3 downto 0) <= ascii_to_nibble(uart_rx_data);
                parse_state <= P_R_END;
              else
                cmd_error_request <= '1'; parse_state <= P_IDLE;
              end if;
            when P_R_END =>
              if (uart_rx_data = x"0D") and (parsed_addr(7) = '0') then
                cmd_read_request <= '1';
              else
                cmd_error_request <= '1';
              end if;
              parse_state <= P_IDLE;
          end case;
        end if;
      end if;
    end if;
  end process;

  -- DAC bring-up, command execution, and ASCII reply serializer.
  process (clk_50mhz)
  begin
    if rising_edge(clk_50mhz) then
      if rst = '1' then
        boot_state    <= BOOT_RESET;
        reset_count   <= 0;
        dac_nrst      <= '0';
        spi_start     <= '0';
        spi_read      <= '0';
        spi_word      <= '0';
        spi_addr      <= (others => '0');
        spi_wdata     <= (others => '0');
        uart_tx_start <= '0';
        uart_tx_data  <= (others => '0');
        reply_index   <= 0;
        reply_length  <= 1;
      else
        spi_start     <= '0';
        uart_tx_start <= '0';

        case boot_state is
          when BOOT_RESET =>
            dac_nrst <= '0';
            if reset_count = RESET_TICKS - 1 then
              reset_count <= 0;
              dac_nrst <= '1';
              boot_state <= BOOT_CLEAR_ERR_START;
            else
              reset_count <= reset_count + 1;
            end if;

          when BOOT_CLEAR_ERR_START =>
            spi_read  <= '0'; spi_word <= '0'; spi_addr <= REG_ERR_STATUS;
            spi_wdata <= x"0001"; spi_start <= '1';
            boot_state <= BOOT_CLEAR_ERR_WAIT;
          when BOOT_CLEAR_ERR_WAIT =>
            if spi_done = '1' then boot_state <= BOOT_RANGE_START; end if;

          when BOOT_RANGE_START =>
            -- CH0_OUTPUT_RANGE = 0b100 selects the ±10 V predefined span.
            spi_read  <= '0'; spi_word <= '0'; spi_addr <= REG_CH0_OUTPUT_RANGE;
            spi_wdata <= x"0004"; spi_start <= '1';
            boot_state <= BOOT_RANGE_WAIT;
          when BOOT_RANGE_WAIT =>
            if spi_done = '1' then boot_state <= BOOT_SCRATCH_WR_START; end if;

          when BOOT_SCRATCH_WR_START =>
            spi_read  <= '0'; spi_word <= '0'; spi_addr <= REG_SCRATCH_PAD;
            spi_wdata <= x"005A"; spi_start <= '1';
            boot_state <= BOOT_SCRATCH_WR_WAIT;
          when BOOT_SCRATCH_WR_WAIT =>
            if spi_done = '1' then boot_state <= BOOT_SCRATCH_RD_START; end if;

          when BOOT_SCRATCH_RD_START =>
            spi_read  <= '1'; spi_word <= '0'; spi_addr <= REG_SCRATCH_PAD;
            spi_wdata <= (others => '0'); spi_start <= '1';
            boot_state <= BOOT_SCRATCH_RD_WAIT;
          when BOOT_SCRATCH_RD_WAIT =>
            if spi_done = '1' then
              if spi_rdata = x"5A" then
                boot_state <= BOOT_ZERO_START;
              else
                boot_state <= BOOT_FAIL;
              end if;
            end if;

          when BOOT_ZERO_START =>
            -- Direct 16-bit write: instruction 0x2A, then MSB at 0x2A and LSB at 0x29.
            spi_read  <= '0'; spi_word <= '1'; spi_addr <= REG_CH0_DAC_16B_MSB;
            spi_wdata <= x"8000"; spi_start <= '1';
            boot_state <= BOOT_ZERO_WAIT;
          when BOOT_ZERO_WAIT =>
            if spi_done = '1' then boot_state <= READY; end if;

          when BOOT_FAIL =>
            -- The scratch-pad readback did not match.  Hold the DAC at its
            -- reset/output-range state and refuse commands until FPGA reset.
            null;

          when READY =>
            if cmd_error_request = '1' then
              reply_mem(0) <= x"45"; reply_mem(1) <= x"52"; reply_mem(2) <= x"52";
              reply_mem(3) <= x"0D"; reply_mem(4) <= x"0A";
              reply_length <= 5; reply_index <= 0;
              boot_state <= REPLY_LAUNCH;
            elsif cmd_write_request = '1' then
              command_word <= parsed_word;
              boot_state <= CMD_WRITE_START;
            elsif cmd_read_request = '1' then
              command_addr <= parsed_addr;
              boot_state <= CMD_READ_START;
            end if;

          when CMD_WRITE_START =>
            spi_read  <= '0'; spi_word <= '1'; spi_addr <= REG_CH0_DAC_16B_MSB;
            spi_wdata <= command_word; spi_start <= '1';
            boot_state <= CMD_WRITE_WAIT;
          when CMD_WRITE_WAIT =>
            if spi_done = '1' then
              reply_mem(0) <= x"4F"; reply_mem(1) <= x"4B";
              reply_mem(2) <= x"0D"; reply_mem(3) <= x"0A";
              reply_length <= 4; reply_index <= 0;
              boot_state <= REPLY_LAUNCH;
            end if;

          when CMD_READ_START =>
            spi_read  <= '1'; spi_word <= '0'; spi_addr <= command_addr(6 downto 0);
            spi_wdata <= (others => '0'); spi_start <= '1';
            boot_state <= CMD_READ_WAIT;
          when CMD_READ_WAIT =>
            if spi_done = '1' then
              reply_mem(0) <= x"52"; -- R
              reply_mem(1) <= nibble_to_ascii(command_addr(7 downto 4));
              reply_mem(2) <= nibble_to_ascii(command_addr(3 downto 0));
              reply_mem(3) <= x"3D"; -- =
              reply_mem(4) <= nibble_to_ascii(spi_rdata(7 downto 4));
              reply_mem(5) <= nibble_to_ascii(spi_rdata(3 downto 0));
              reply_mem(6) <= x"0D"; reply_mem(7) <= x"0A";
              reply_length <= 8; reply_index <= 0;
              boot_state <= REPLY_LAUNCH;
            end if;

          when REPLY_LAUNCH =>
            uart_tx_data <= reply_mem(reply_index);
            uart_tx_start <= '1';
            boot_state <= REPLY_WAIT_BUSY;
          when REPLY_WAIT_BUSY =>
            if uart_tx_busy = '1' then boot_state <= REPLY_WAIT_DONE; end if;
          when REPLY_WAIT_DONE =>
            if uart_tx_busy = '0' then
              if reply_index = reply_length - 1 then
                boot_state <= READY;
              else
                reply_index <= reply_index + 1;
                boot_state <= REPLY_LAUNCH;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
