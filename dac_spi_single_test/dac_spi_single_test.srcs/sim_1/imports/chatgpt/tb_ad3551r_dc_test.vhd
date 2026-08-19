-- Self-checking VHDL-2008 simulation testbench for ad3551r_dc_test_top.
-- The behavioral DAC model implements the small register subset used by the
-- bring-up design.  It is intentionally not an analog model.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.env.all;
use work.ad3551r_test_pkg.all;

entity tb_ad3551r_dc_test is
end entity;

architecture sim of tb_ad3551r_dc_test is
  constant CLK_PERIOD    : time := 20 ns;
  constant UART_BIT_TIME : time := 8680 ns; -- 50 MHz / 434 clocks per bit

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '0';
  signal rs422_rx    : std_logic := '1';
  signal rs422_tx    : std_logic;
  signal rs422_tx_en : std_logic := 'Z';
  signal rs422_tx_nen: std_logic := 'Z';
  signal dac_nalert  : std_logic := '1';
  signal dac_nrst    : std_logic;
  signal dac_nload   : std_logic;
  signal dac_ncs     : std_logic;
  signal dac_sclk    : std_logic;
  signal dac_sdio0   : std_logic;
  signal dac_sdio1   : std_logic := 'Z';
  signal dac_sdio2   : std_logic := 'Z';
  signal dac_sdio3   : std_logic := 'Z';
  signal led_ready   : std_logic;
  signal led_alert   : std_logic;

  type reg_mem_t is array (0 to 127) of byte_t;
  function reset_registers return reg_mem_t is
    variable r : reg_mem_t := (others => x"00");
  begin
    r(0)  := x"10"; -- INTERFACE_CONFIG_A
    r(1)  := x"08"; -- INTERFACE_CONFIG_B: 7-bit addressing
    r(3)  := x"04"; -- CHIP_TYPE
    r(4)  := x"0A"; -- PRODUCT_ID_L
    r(5)  := x"40"; -- PRODUCT_ID_H
    r(6)  := x"05"; -- CHIP_GRADE
    r(11) := x"83"; -- SPI_REVISION
    r(12) := x"56"; -- VENDOR_L
    r(13) := x"04"; -- VENDOR_H
    r(17) := x"01"; -- ERR_STATUS: reset bit asserted after reset
    return r;
  end function;

  signal model_regs     : reg_mem_t := reset_registers;
  signal instr_shift    : byte_t := (others => '0');
  signal data_shift     : byte_t := (others => '0');
  signal byte_bit_count : integer range 0 to 7 := 0;
  signal instruction_seen : std_logic := '0';
  signal model_read       : std_logic := '0';
  signal model_address    : integer range 0 to 127 := 0;
  signal model_read_bit   : integer range 0 to 7 := 7;
  signal model_sdio1      : std_logic := 'Z';

  constant EXPECTED_REPLY : byte_array_t(0 to 27) := (
    x"52", x"30", x"41", x"3D", x"35", x"41", x"0D", x"0A", -- R0A=5A\r\n
    x"4F", x"4B", x"0D", x"0A",                         -- OK\r\n
    x"52", x"31", x"39", x"3D", x"30", x"34", x"0D", x"0A", -- R19=04\r\n
    x"52", x"30", x"33", x"3D", x"30", x"34", x"0D", x"0A"  -- R03=04\r\n
  );
  signal checked_reply_bytes : integer range 0 to EXPECTED_REPLY'length := 0;

  procedure send_uart_byte (
    signal line : out std_logic;
    constant data : in byte_t
  ) is
  begin
    line <= '0';
    wait for UART_BIT_TIME;
    for i in 0 to 7 loop
      line <= data(i);
      wait for UART_BIT_TIME;
    end loop;
    line <= '1';
    wait for UART_BIT_TIME;
  end procedure;
begin
  clk <= not clk after CLK_PERIOD / 2;
  dac_sdio1 <= model_sdio1;

  dut : entity work.ad3551r_dc_test_top
    generic map (
      CLK_HZ => 50_000_000,
      UART_BAUD => 115_200,
      SPI_HZ => 5_000_000
    )
    port map (
      clk_50mhz => clk,
      rst => rst,
      rs422_rx => rs422_rx,
      rs422_tx => rs422_tx,
	  rs422_tx_nen=>rs422_tx_nen,
	  rs422_tx_en=>rs422_tx_en,
      dac_nalert => dac_nalert,
      dac_nrst => dac_nrst,
      dac_nload => dac_nload,
      dac_ncs => dac_ncs,
      dac_sclk => dac_sclk,
      dac_sdio0 => dac_sdio0,
      dac_sdio1 => dac_sdio1,
      dac_sdio2 => dac_sdio2,
      dac_sdio3 => dac_sdio3,
      led_ready => led_ready,
      led_alert => led_alert
    );

  -- Behavioral AD3551R classic-SPI model.  It supports 7-bit instruction
  -- addressing, one-byte register accesses, and descending 16-bit writes.
  dac_model : process (dac_nrst, dac_ncs, dac_sclk)
    variable complete_byte : byte_t;
    variable complete_instruction : byte_t;
  begin
    if dac_nrst = '0' then
      model_regs       <= reset_registers;
      instr_shift      <= (others => '0');
      data_shift       <= (others => '0');
      byte_bit_count   <= 0;
      instruction_seen <= '0';
      model_read       <= '0';
      model_address    <= 0;
      model_read_bit   <= 7;
      model_sdio1      <= 'Z';
    elsif dac_ncs = '1' then
      byte_bit_count   <= 0;
      instruction_seen <= '0';
      model_read       <= '0';
      model_read_bit   <= 7;
      model_sdio1      <= 'Z';
    elsif rising_edge(dac_sclk) then
      if instruction_seen = '0' then
        if byte_bit_count = 7 then
          complete_instruction := instr_shift(6 downto 0) & dac_sdio0;
          instruction_seen <= '1';
          model_read       <= complete_instruction(7);
          model_address    <= to_integer(unsigned(complete_instruction(6 downto 0)));
          byte_bit_count   <= 0;
          model_read_bit   <= 7;
        else
          instr_shift <= instr_shift(6 downto 0) & dac_sdio0;
          byte_bit_count <= byte_bit_count + 1;
        end if;
      elsif model_read = '0' then
        if byte_bit_count = 7 then
          complete_byte := data_shift(6 downto 0) & dac_sdio0;
          model_regs(model_address) <= complete_byte;
          if model_address > 0 then
            model_address <= model_address - 1; -- reset default address direction is descending
          end if;
          byte_bit_count <= 0;
        else
          data_shift <= data_shift(6 downto 0) & dac_sdio0;
          byte_bit_count <= byte_bit_count + 1;
        end if;
      end if;
    elsif falling_edge(dac_sclk) then
      if (instruction_seen = '1') and (model_read = '1') then
        model_sdio1 <= model_regs(model_address)(model_read_bit);
        if model_read_bit = 0 then
          model_sdio1 <= 'Z';
        else
          model_read_bit <= model_read_bit - 1;
        end if;
      end if;
    end if;
  end process;

  -- Decode and verify the UART replies generated by the FPGA.
  uart_reply_checker : process
    variable received : byte_t;
    variable reply_index : integer := 0;
  begin
    loop
      wait until falling_edge(rs422_tx);
      wait for UART_BIT_TIME + UART_BIT_TIME / 2;
      for i in 0 to 7 loop
        received(i) := rs422_tx;
        wait for UART_BIT_TIME;
      end loop;
      assert rs422_tx = '1'
        report "UART reply has an invalid stop bit" severity failure;
      assert received = EXPECTED_REPLY(reply_index)
        report "Unexpected UART reply byte at index " & integer'image(reply_index)
        severity failure;
      reply_index := reply_index + 1;
      checked_reply_bytes <= reply_index;
    end loop;
  end process;

  stimulus : process
  begin
    rst <= '0';
    wait for 1 us;
    rst <= '1';

    wait until led_ready = '1' for 500 us;
    assert led_ready = '1'
      report "Startup failed: scratch-pad SPI readback did not return 5A"
      severity failure;
    assert dac_nload = '1' report "nLOAD must remain inactive for direct DAC writes" severity failure;
    assert model_regs(16#19#) = x"04"
      report "The ±10 V output-range register was not configured" severity failure;
    assert model_regs(16#2A#) = x"80" and model_regs(16#29#) = x"00"
      report "Initial DAC code was not written as 8000" severity failure;

    -- Read scratch pad: expected reply R0A=5A.
    send_uart_byte(rs422_rx, x"52"); -- R
    send_uart_byte(rs422_rx, x"30"); -- 0
    send_uart_byte(rs422_rx, x"41"); -- A
    send_uart_byte(rs422_rx, x"0D"); -- CR
    wait for 900 us;

    -- Write a non-default DAC code: expected reply OK.
    send_uart_byte(rs422_rx, x"57"); -- W
    send_uart_byte(rs422_rx, x"31"); -- 1
    send_uart_byte(rs422_rx, x"32"); -- 2
    send_uart_byte(rs422_rx, x"33"); -- 3
    send_uart_byte(rs422_rx, x"34"); -- 4
    send_uart_byte(rs422_rx, x"0D"); -- CR
    wait for 500 us;
    assert model_regs(16#2A#) = x"12" and model_regs(16#29#) = x"34"
      report "Docklight W1234 command did not update the DAC code" severity failure;

    -- Read configured output range and chip type.
    send_uart_byte(rs422_rx, x"52"); -- R
    send_uart_byte(rs422_rx, x"31"); -- 1
    send_uart_byte(rs422_rx, x"39"); -- 9
    send_uart_byte(rs422_rx, x"0D"); -- CR
    wait for 900 us;
    send_uart_byte(rs422_rx, x"52"); -- R
    send_uart_byte(rs422_rx, x"30"); -- 0
    send_uart_byte(rs422_rx, x"33"); -- 3
    send_uart_byte(rs422_rx, x"0D"); -- CR

    wait until checked_reply_bytes = EXPECTED_REPLY'length for 3 ms;
    assert checked_reply_bytes = EXPECTED_REPLY'length
      report "Testbench timed out waiting for all UART replies" severity failure;
    report "PASS: AD3551R DC-output and readback simulation completed" severity note;
    finish;
  end process;
end architecture;
