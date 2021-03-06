--**********************************************************************
-- Copyright (c) 2013-2014 by XESS Corp <http://www.xess.com>.
-- All rights reserved.
--
-- This library is free software; you can redistribute it and/or
-- modify it under the terms of the GNU Lesser General Public
-- License as published by the Free Software Foundation; either
-- version 3.0 of the License, or (at your option) any later version.
-- 
-- This library is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- Lesser General Public License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public
-- License along with this library.  If not, see 
-- <http://www.gnu.org/licenses/>.
--**********************************************************************

--**********************************************************************
-- This module provides an interface between a host PC and an SPI
-- peripheral chip that operates as follows:
--
-- 1. A Python program on the host PC issues commands for reading or
--    writing an SPI chip connected to the XuLA FPGA board.
-- 2. The SPI commands are turned into JTAG bit strings that can be sent
--    to the FPGA through its JTAG port.
-- 3. The JTAG bit strings are packaged as USB packets and are sent to
--    the interface microcontroller on the XuLA board.
-- 4. The microcontroller unpacks the JTAG bitstrings and injects them
--    into the FPGA through its JTAG port.
-- 5. The HostIoToRam module in the FPGA decodes the bit strings and
--    interprets them as reads or writes to the registers of the
--    SPI module.
-- 6. The SPI module transfers data to/from the external SPI chip as
--    directed by the settings in its registers.
-- 7. Any data or status bytes from the SPI interface registers are
--    returned to the microcontroller by the HostIoToRam module as JTAG
--    bit strings through the JTAG interface.
-- 8. The microcontroller returns the JTAG bit strings to the host
--    PC as USB packets.
-- 9. The JTAG bit strings are unpacked from the USB packets and
--    turned into data or status bytes.
--
--                   +------------------XuLA Board------------------+
-- +---------+       | +---uC---+          +---------FPGA---------+ |
-- |         |       | |        |          |                      |---> SSEL
-- |         |       | |        |          |                      |<--> SCK
-- | Host PC |<--USB-->| PIC18F |<--JTAG-->| HostIoToRam <--> SPI |---> MOSI
-- |         |       | |        |          |                      |<--- MISO
-- +---------+       | +--------+          +----------------------+ |
--                   +----------------------------------------------+
--
--**********************************************************************


library IEEE, XESS;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use XESS.CommonPckg.all;
use XESS.HostIoPckg.all;
use work.XessBoardPckg.all;

package HostIoToSpiPckg is

  component HostIoToSpi is
    generic (
      FREQ_G             : real             := 100.0;  -- Main clock frequency (MHz).
      SPI_FREQ_G         : real             := 25.0;  -- SPI clock frequency (MHz).
      DATA_LENGTH_G      : natural          := 8;  -- Length of SPI data shift-register.
      CPOL_G             : std_logic        := LO;  -- SCK polarity (0=normally low, 1=normally high).
      CPHA_G             : std_logic        := HI;  -- SCK phase (0=sample on leading edge, 1=sample on trailing edge).
      ID_G               : std_logic_vector := "11111111";  -- The ID this module responds to.
      PYLD_CNTR_LENGTH_G : natural          := 32;  -- Length of payload bit counter.
      FPGA_DEVICE_G      : FpgaFamily_t     := FPGA_FAMILY_C;  -- FPGA device type.
      TAP_USER_INSTR_G   : TapUserInstr_t   := TAP_USER_INSTR_C;  -- USER instruction this module responds to.
      SIMPLE_G           : boolean          := false;  -- If true, include BscanToHostIo module in this module.
      SYNC_G             : boolean          := true  -- If true, sync this module with the SPI clock domain.
      );
    port (
      reset_i     : in  std_logic := LO;  -- Active-high reset signal.
      clk_i       : in  std_logic;      -- Master clock.
      -- Interface to BscanHostIo. (Used only if SIMPLE_G is false.)
      inShiftDr_i : in  std_logic := LO;  -- True when USER JTAG instruction is active and the TAP FSM is in the Shift-DR state.
      drck_i      : in  std_logic := LO;  -- Bit clock. TDI clocked in on rising edge, TDO sampled on falling edge.
      tdi_i       : in  std_logic := LO;  -- Bit from the host to the memory.
      tdo_o       : out std_logic;      -- Bit from the memory to the host.
      -- SPI interface.
      ssel_o      : out std_logic;      -- SPI chip-select.
      sck_o       : out std_logic;      -- SPI clock line.
      mosi_o      : out std_logic;      -- SPI master output to slave input.
      miso_i      : in  std_logic       -- SPI master input from slave output.
      );
  end component;

  component HostIoToSpiTest is
    port (
      fpgaClk_i : in  std_logic;        -- XuLA 12 MHz clock.
      ssel_o    : out std_logic;        -- SPI chip-select.
      sck_o     : out std_logic;        -- SPI clock line.
      mosi_o    : out std_logic;        -- SPI master output to slave input.
      miso_i    : in  std_logic         -- SPI master input from slave output.
      );
  end component;

end package;




library IEEE, XESS;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use XESS.CommonPckg.all;
use XESS.HostIoPckg.all;
use XESS.SpiPckg.all;
use work.XessBoardPckg.all;

entity HostIoToSpi is
  generic (
    FREQ_G             : real             := 100.0;  -- Main clock frequency (MHz).
    SPI_FREQ_G         : real             := 25.0;  -- SPI clock frequency (MHz).
    DATA_LENGTH_G      : natural          := 8;  -- Length of SPI data shift-register.
    CPOL_G             : std_logic        := LO;  -- SCK polarity (0=normally low, 1=normally high).
    CPHA_G             : std_logic        := HI;  -- SCK phase (0=sample on leading edge, 1=sample on trailing edge).
    ID_G               : std_logic_vector := "11111111";  -- The ID this module responds to.
    PYLD_CNTR_LENGTH_G : natural          := 32;  -- Length of payload bit counter.
    FPGA_DEVICE_G      : FpgaFamily_t     := FPGA_FAMILY_C;  -- FPGA device type.
    TAP_USER_INSTR_G   : TapUserInstr_t   := TAP_USER_INSTR_C;  -- USER instruction this module responds to.
    SIMPLE_G           : boolean          := false;  -- If true, include BscanToHostIo module in this module.
    SYNC_G             : boolean          := true  -- If true, sync this module with the SPI clock domain.
    );
  port (
    reset_i     : in  std_logic := LO;  -- Active-high reset signal.
    clk_i       : in  std_logic;        -- Master clock.
    -- Interface to BscanHostIo. (Used only if SIMPLE_G is false.)
    inShiftDr_i : in  std_logic := LO;  -- True when USER JTAG instruction is active and the TAP FSM is in the Shift-DR state.
    drck_i      : in  std_logic := LO;  -- Bit clock. TDI clocked in on rising edge, TDO sampled on falling edge.
    tdi_i       : in  std_logic := LO;  -- Bit from the host to the memory.
    tdo_o       : out std_logic;        -- Bit from the memory to the host.
    -- SPI interface.
    ssel_o      : out std_logic;        -- SPI chip-select.
    sck_o       : out std_logic;        -- SPI clock line.
    mosi_o      : out std_logic;        -- SPI master output to slave input.
    miso_i      : in  std_logic         -- SPI master input from slave output.
    );
end entity;


architecture arch of HostIoToSpi is
  signal addr_s         : std_logic_vector(1 downto 0);  -- Register address in SPI interface.
  signal wr_s           : std_logic;  -- Active-high write to SPI interface register.
  signal rd_s           : std_logic;  -- Active-high read of SPI interface register.
  signal dataFromHost_s : std_logic_vector(DATA_LENGTH_G-1 downto 0);  -- Data from PC to SPI slave.
  signal dataToHost_s   : std_logic_vector(DATA_LENGTH_G-1 downto 0);  -- Data from SPI slave to PC.
  signal begun_s        : std_logic;  -- When true, R/W operation to SPI interface has begun.
  signal done_s         : std_logic;  -- When true, R/W operation to SPI interface complete.
  
begin

  -- Instantiate an interface between the JTAG port and the SPI module.
  u1 : HostIoToRam
    generic map(
      ID_G               => ID_G,
      PYLD_CNTR_LENGTH_G => PYLD_CNTR_LENGTH_G,
      FPGA_DEVICE_G      => FPGA_DEVICE_G,
      TAP_USER_INSTR_G   => TAP_USER_INSTR_G,
      SIMPLE_G           => SIMPLE_G,
      SYNC_G             => true,
      ADDR_INC_G         => 0  -- R/W sequences do not automatically advance the register address.
     -- (This is done to support mutli-byte reads and writes.)
      )
    port map(
      reset_i        => reset_i,        -- Active-high reset input.
      clk_i          => clk_i,          -- Master clock input.
      -- JTAG interface.
      inShiftDr_i    => inShiftDr_i,
      drck_i         => drck_i,
      tdi_i          => tdi_i,
      tdo_o          => tdo_o,
      -- Interface to SPI module.      
      addr_o         => addr_s,         -- SPI register address from PC.
      wr_o           => wr_s,           -- Write control from PC.
      rd_o           => rd_s,           -- Read control from PC.
      dataFromHost_o => dataFromHost_s,  -- Data from PC to SPI.
      dataToHost_i   => dataToHost_s,   -- Data from SPI to PC.
      opBegun_i      => begun_s,  -- This keeps R/W controls active for entire bus cycle.
      done_i         => done_s  -- True when the SPI register R/W is completed.
      );

  -- Instantiate an SPI master interface module.
  u2 : SpiMaster
    generic map(
      FREQ_G     => FREQ_G,             -- Main clock frequency (MHz).
      SPI_FREQ_G => SPI_FREQ_G,         -- SPI clock frequency (MHz).
      CPOL_G     => CPOL_G,             -- SCK polarity.
      CPHA_G     => CPHA_G              -- Sampling edge.
      )
    port map(
      rst_i   => reset_i,               -- Active-high reset input.
      clk_i   => clk_i,                 -- Master clock input.
      addr_i  => addr_s,                -- Register address from PC.
      data_i  => dataFromHost_s,        -- Data from PC.
      data_o  => dataToHost_s,          -- Data to PC.
      wr_i    => wr_s,                  -- Write control from PC.
      rd_i    => rd_s,                  -- Read control from PC.
      begun_o => begun_s,               -- True when R/W operation has begun.
      done_o  => done_s,                -- True when R/W operation completed.
      ssel_o  => ssel_o,                -- SPI chip-select line.
      sck_o   => sck_o,                 -- SPI clock line.
      mosi_o  => mosi_o,                -- SPI data from master to slave.
      miso_i  => miso_i                 -- SPI data from slave to master.
      );

end architecture;




--**********************************************************************
-- Thiis is a simple design for testing the interface between a host PC
-- and an SPI peripheral chip.
--**********************************************************************

library IEEE, XESS;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use XESS.CommonPckg.all;
use XESS.ClkGenPckg.all;
use XESS.HostIoToSpiPckg.all;

entity HostIoToSpiTest is
  port (
    fpgaClk_i : in  std_logic;          -- XuLA 12 MHz clock.
    ssel_o    : out std_logic;          -- SPI chip-select.
    sck_o     : out std_logic;          -- SPI clock line.
    mosi_o    : out std_logic;          -- SPI master output to slave input.
    miso_i    : in  std_logic           -- SPI master input from slave output.
    );
end entity;

architecture arch of HostIoToSpiTest is
  signal clk_s   : std_logic;           -- Clock.
  signal reset_s : std_logic := LO;     -- Active-high reset.
begin

  -- Generate 100 MHz clock from 12 MHz XuLA clock.
  u0 : ClkGen generic map(CLK_MUL_G => 25, CLK_DIV_G => 3) port map(i => fpgaClk_i, o => clk_s);

  -- Generate a reset pulse to initialize the modules.
  process (clk_s)
    variable rstCnt_v : integer range 0 to 15 := 10;  -- Set length of rst pulse.
  begin
    if rising_edge(clk_s) then
      reset_s <= HI;                    -- Activate rst.
      if rstCnt_v = 0 then
        reset_s <= LO;                  -- Release rst when counter hits 0.
      else
        rstCnt_v := rstCnt_v - 1;
      end if;
    end if;
  end process;

  -- Instantiate the JTAG-to-SPI interface.
  u1 : HostIoToSpi
    generic map(
      SIMPLE_G => true
      )
    port map(
      reset_i => reset_s,
      clk_i   => clk_s,
      ssel_o  => ssel_o,
      sck_o   => sck_o,
      mosi_o  => mosi_o,
      miso_i  => miso_i
      );

end architecture;

