/** @file
 *
 *  Differentiated System Definition Table (DSDT) for the Yijiahe JM10-3588.
 *
 *  This platform is ACPI-only: no device tree is embedded in the firmware and
 *  none is published to the OS (PcdConfigTableModeDefault is
 *  CONFIG_TABLE_MODE_ACPI in JM10.dsc). Everything the OS is told about the
 *  board therefore has to be in these tables.
 *
 *  The layout below is the ACPI translation of the board configuration that
 *  the armbian-build-jm10 tree carries in
 *  userpatches/kernel/rockchip-6.1-yjh-jm10/ (rk3588-yjh-jm10.dts):
 *
 *    - eMMC (sdhci/sdhci@fe2e0000), 8 bit, HS400 with enhanced strobe
 *    - SATA0 (sata@fe210000) on combphy0 - the "M.2" slot is really mSATA.
 *      Only engine 0 exists; ATA1/ATA2 are switched off by combphy1/2 being
 *      PCIe/USB3 (see AcpiDsdtFixupStatus in AcpiPlatformDxe).
 *    - PCIe2x1l0 (pcie@fe170000) on combphy1 - the on-board AP6275P Wi-Fi.
 *      pcie3x4/pcie3x2 are not routed; PcdPcie30Supported is FALSE and only
 *      PCI2 survives the _STA fixup.
 *    - USB: USB2 hosts, the Type-C OTG port and the USB3 host on combphy2.
 *    - GMAC0 (ethernet@fe1b0000) - see the caveat in Gmac0.asl and below.
 *    - I2C0 (RK8602/RK8603 CPU regulators), I2C1 (RK8602 NPU regulator),
 *      I2C6 (HYM8563 RTC), I2C7 (RT5651 audio codec).
 *    - I2S0 to the RT5651 codec.
 *    - The debug UART2, the GPIO banks and the DMA controllers.
 *
 *  Deliberately absent, with reasons:
 *
 *    - SDHCI/SD (sdmmc@fe2c0000). The vendor device tree enables &sdmmc, but
 *      the board has no SD slot (RK_SD_ENABLE is FALSE in JM10.dsc, for the
 *      same reason) and the node would have to borrow the generic
 *      SDMMC_DET/GPIO0_A4 card-detect wiring that this board does not have.
 *      Add `include ("Sdhc.asl")` here and set PcdRkSdmmcCardDetectBroken if
 *      a slot turns out to exist.
 *    - SPI: the only SPI master in use (spi2) carries the RK806 PMIC, which
 *      the firmware owns; there is no SPI NOR flash (RK_NOR_FLASH_ENABLE is
 *      FALSE).
 *    - UARTs other than UART2. The device tree enables uart0/1/3/4/5/7/9, and
 *      the OS image uses uart1 for Bluetooth (rk3588-bluetooth.service on
 *      /dev/ttyS1). Only UART2 is described here, because it is the one the
 *      firmware itself brings up (the debug console). The others are left
 *      unmuxed when the firmware hands over - there is no platform hook that
 *      muxes a UART pin group - so an ACPI device for them would only give the
 *      OS a dead port. Bluetooth over UART1 therefore does not come up.
 *    - The MV88E6190 DSA switch. It is reachable over MDIO behind GMAC0, but
 *      Linux's DSA framework is device-tree only - there is no way to state a
 *      switch-with-ports topology in ACPI. MAC0 is described so the MAC itself
 *      is known to the OS, but the seven RJ45 ports cannot be brought up from
 *      these tables. This is the one piece of the board that pure ACPI cannot
 *      express; the device tree remains the only way to drive that switch.
 *    - The PWM fan (pwm15) and the status LED (gpio3 RK_PB7). Both are wired
 *      up and driven by the firmware (PwmFanIoSetup / PlatformSetStatusLed in
 *      RockchipPlatformLib), and there is no ACPI description for the RK3588
 *      PWM controller, so the OS is not given either.
 *
 *  Copyright (c) 2020, Pete Batard <pete@akeo.ie>
 *  Copyright (c) 2018-2020, Andrey Warkentin <andrey.warkentin@gmail.com>
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Copyright (c) 2021, ARM Limited. All rights reserved.
 *  Copyright (c) 2026, Yijiahe JM10 port
 *
 *  SPDX-License-Identifier: BSD-2-Clause-Patent
 **/

#include "AcpiTables.h"

// Audio topology tag consumed by I2s.asl.
#define BOARD_I2S0_TPLG "i2s-jack"

DefinitionBlock ("Dsdt.aml", "DSDT", 2, "RKCP  ", "RK3588  ", 2)
{
  Scope (\_SB_)
  {
    include ("DsdtCommon.asl")

    include ("Cpu.asl")

    include ("Pcie.asl")
    include ("Sata.asl")
    include ("Emmc.asl")
    include ("Dma.asl")
    include ("Gmac0.asl")
    include ("Gpio.asl")
    include ("I2c.asl")
    include ("Uart.asl")

    include ("I2s.asl")

    include ("Usb2Host.asl")
    include ("Usb3Host0.asl")
    include ("Usb3Host1.asl")
    include ("Usb3Host2.asl")

    // Board devices that hang off the I2C buses.
    Scope (I2C6) {
      include ("Hym8563.asl")
    }

    Scope (I2C7) {
      include ("Rt5651.asl")
    }
  }
}
