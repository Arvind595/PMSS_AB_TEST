# AD3551R DC bring-up test

Compile the VHDL files in this order:

1. `ad3551r_test_pkg.vhd`
2. `uart_rx_8n1.vhd`
3. `uart_tx_8n1.vhd`
4. `ad3551r_spi_master.vhd`
5. `ad3551r_dc_test_top.vhd`
6. `tb_ad3551r_dc_test.vhd` (simulation only)

The top-level is `ad3551r_dc_test_top`.  It has scalar DAC ports for one
AD3551R; map them to DAC index 0 in the final 16-DAC board design.  Assign all
DAC digital pins to a 1.8 V bank and use the `LVCMOS18` I/O standard.

The design uses classic SPI Mode 0 at 5 MHz.  `DAC_MODE_QSPI` is held low;
`SDIO0` is FPGA-to-DAC, `SDIO1` is DAC-to-FPGA, and `SDIO2/3` are tri-stated.
It holds `nLOAD` high because it writes the DAC register directly.

At power-up it holds `nRST` low for 100 us, clears the reset alarm, selects
the predefined `+/-10 V` span (`CH0_OUTPUT_RANGE = 0x04`), checks the scratch
pad by writing and reading `0x5A`, and writes code `0x8000` (nominally 0 V).

Configure Docklight for 115200 baud, 8 data bits, no parity, 1 stop bit, and
append carriage return (`CR`, hex `0D`) to every command.  Commands are ASCII:

```
W0000<CR>    approximately -10 V
W8000<CR>    approximately 0 V
WFFFF<CR>    approximately +10 V
R03<CR>      read CHIP_TYPE
R04<CR>      read PRODUCT_ID_L
R05<CR>      read PRODUCT_ID_H
R0A<CR>      read scratch pad; expected 5A after startup
R19<CR>      read output-range register; expected 04
R17<CR>      read error-status register
```

Successful writes reply `OK`.  A read of address `0A`, for example, replies
`R0A=5A`.  The `led_ready` output goes high only after the start-up sequence,
including successful scratch-pad readback, has finished.  If that readback
fails, `led_ready` remains low and the design refuses commands until reset.
`led_alert` goes high if the active-low DAC `nALERT` pin is low.

Do not connect a sensitive load until the startup sequence and the `R0A` read
are confirmed.  Check the DAC clock, chip select, and SDIO0 on the oscilloscope
before diagnosing the analog output.

## Simulation

Set `tb_ad3551r_dc_test` as the Vivado simulation top.  The testbench includes
a behavioral AD3551R register/SPI model and checks the complete UART replies.
It verifies startup scratch-pad readback, the `+/-10 V` range configuration,
the initial `0x8000` code, and Docklight-style `R0A`, `W1234`, `R19`, and
`R03` commands.  A successful run ends with:

```
PASS: AD3551R DC-output and readback simulation completed
```

This is a digital protocol test.  It does not model the AD3551R current output,
AD8065, power rails, or analog settling behavior.
