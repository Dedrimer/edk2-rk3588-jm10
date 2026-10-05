/** @file
*
*  Yijiahe JM10-3588 (RK3588) board hooks.
*
*  Copyright (c) 2021, Rockchip Limited. All rights reserved.
*  Copyright (c) 2023-2024, Mario Bălănică <mariobalanica02@gmail.com>
*  Copyright (c) 2026, Yijiahe JM10 port
*
*  SPDX-License-Identifier: BSD-2-Clause-Patent
*
*  Hardware notes (all pin references come from the vendor device tree
*  rk3588-yjh-jm10.dts):
*
*   - No SD card slot and no SPI NOR flash. eMMC (HS400) and mSATA (SATA0) are
*     the only storage.
*   - Seven RJ45 ports hang off a Marvell MV88E6190 DSA switch; GMAC0 reaches
*     the switch through a fixed 1000 Mbit RGMII link. RK3588_GMAC_ENABLE is
*     FALSE in JM10.dsc, so the GmacIomux()/GmacIoPhyReset() hooks below are
*     not reached on a default build - they are kept correct for the day the
*     MAC is enabled.
*   - No TTL debug UART is routed. UEFI's debug output stays on UART2, so the
*     only usable console is the graphical one (HDMI / Type-C DP).
*
**/

#include <Base.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/GpioLib.h>
#include <Library/RK806.h>
#include <Library/Rk3588Pcie.h>
#include <Library/PWMLib.h>
#include <Soc.h>
#include <VarStoreData.h>

static struct regulator_init_data  rk806_init_data[] = {
  /* Master PMIC */
  RK8XX_VOLTAGE_INIT (MASTER_BUCK1,  750000),
  RK8XX_VOLTAGE_INIT (MASTER_BUCK3,  750000),
  RK8XX_VOLTAGE_INIT (MASTER_BUCK4,  750000),
  RK8XX_VOLTAGE_INIT (MASTER_BUCK5,  850000),
  // RK8XX_VOLTAGE_INIT(MASTER_BUCK6, 750000),
  RK8XX_VOLTAGE_INIT (MASTER_BUCK7,  2000000),
  RK8XX_VOLTAGE_INIT (MASTER_BUCK8,  3300000),
  RK8XX_VOLTAGE_INIT (MASTER_BUCK10, 1800000),

  RK8XX_VOLTAGE_INIT (MASTER_NLDO1,  750000),
  RK8XX_VOLTAGE_INIT (MASTER_NLDO2,  850000),
  RK8XX_VOLTAGE_INIT (MASTER_NLDO3,  750000),
  RK8XX_VOLTAGE_INIT (MASTER_NLDO4,  850000),
  RK8XX_VOLTAGE_INIT (MASTER_NLDO5,  750000),

  RK8XX_VOLTAGE_INIT (MASTER_PLDO1,  1800000),
  RK8XX_VOLTAGE_INIT (MASTER_PLDO2,  1800000),
  RK8XX_VOLTAGE_INIT (MASTER_PLDO3,  1200000),
  RK8XX_VOLTAGE_INIT (MASTER_PLDO4,  3300000),
  RK8XX_VOLTAGE_INIT (MASTER_PLDO5,  3300000),
  RK8XX_VOLTAGE_INIT (MASTER_PLDO6,  1800000),

  /* Single RK806 on this platform */
};

VOID
EFIAPI
SdmmcIoMux (
  VOID
  )
{
  /*
   * The JM10 has no SD card slot (RK_SD_ENABLE is FALSE in JM10.dsc, so the
   * SD stack is not built and this is never called). Left as a no-op on
   * purpose rather than pin-muxing an SD interface that does not exist.
   */
}

VOID
EFIAPI
SdhciEmmcIoMux (
  VOID
  )
{
  /* sdhci0 iomux (eMMC) */
  BUS_IOC->GPIO2A_IOMUX_SEL_L = (0xFFFFUL << 16) | (0x1111); // EMMC_CMD,EMMC_CLKOUT,EMMC_DATASTROBE,EMMC_RSTN
  BUS_IOC->GPIO2D_IOMUX_SEL_L = (0xFFFFUL << 16) | (0x1111); // EMMC_D0,EMMC_D1,EMMC_D2,EMMC_D3
  BUS_IOC->GPIO2D_IOMUX_SEL_H = (0xFFFFUL << 16) | (0x1111); // EMMC_D4,EMMC_D5,EMMC_D6,EMMC_D7
}

#define NS_CRU_BASE       0xFD7C0000
#define CRU_CLKSEL_CON59  0x03EC
#define CRU_CLKSEL_CON78  0x0438

VOID
EFIAPI
Rk806SpiIomux (
  VOID
  )
{
  /* io mux */
  PMU1_IOC->GPIO0A_IOMUX_SEL_H = (0x0FF0UL << 16) | 0x0110;
  PMU1_IOC->GPIO0B_IOMUX_SEL_L = (0xF0FFUL << 16) | 0x1011;
  MmioWrite32 (NS_CRU_BASE + CRU_CLKSEL_CON59, (0x00C0UL << 16) | 0x0080);
}

VOID
EFIAPI
Rk806Configure (
  VOID
  )
{
  UINTN  RegCfgIndex;

  RK806Init ();

  RK806PinSetFunction (MASTER, 1, 2); // rk806_dvs1_pwrdn

  for (RegCfgIndex = 0; RegCfgIndex < ARRAY_SIZE (rk806_init_data); RegCfgIndex++) {
    RK806RegulatorInit (rk806_init_data[RegCfgIndex]);
  }
}

VOID
EFIAPI
SetCPULittleVoltage (
  IN UINT32  Microvolts
  )
{
  struct regulator_init_data  Rk806CpuLittleSupply =
    RK8XX_VOLTAGE_INIT (MASTER_BUCK2, Microvolts);

  RK806RegulatorInit (Rk806CpuLittleSupply);
}

VOID
EFIAPI
NorFspiIomux (
  VOID
  )
{
  /*
   * The JM10 has no SPI NOR flash (RK_NOR_FLASH_ENABLE is FALSE in JM10.dsc),
   * and the vendor device tree does not describe an FSPI flash either. Do not
   * claim the FSPI pins.
   */
}

VOID
EFIAPI
GmacIomux (
  IN UINT32  Id
  )
{
  /*
   * Not reached on a default build: RK3588_GMAC_ENABLE is FALSE, because the
   * MAC leads into the MV88E6190 switch and the firmware cannot program the
   * switch. Kept complete for the case where the MAC is enabled to debug the
   * link towards the switch (see JM10.dsc).
   */
  switch (Id) {
    case 0:
      /* gmac0 iomux (RGMII to the MV88E6190 CPU port) */
      BUS_IOC->GPIO2A_IOMUX_SEL_H = (0xFF00UL << 16) | 0x1100;
      BUS_IOC->GPIO2B_IOMUX_SEL_L = (0xFFFFUL << 16) | 0x1111;
      BUS_IOC->GPIO2B_IOMUX_SEL_H = (0xFF00UL << 16) | 0x1100;
      BUS_IOC->GPIO2C_IOMUX_SEL_L = (0x0FFFUL << 16) | 0x0111;
      BUS_IOC->GPIO4C_IOMUX_SEL_L = (0xFF00UL << 16) | 0x1100;
      BUS_IOC->GPIO4C_IOMUX_SEL_H = (0x00FFUL << 16) | 0x0011;

      /* switch reset, vcc3v3_pcie30 / switch reset gpio (gpio4 RK_PB3) */
      GpioPinSetDirection (4, GPIO_PIN_PB3, GPIO_PIN_OUTPUT);
      break;
    default:
      break;
  }
}

VOID
EFIAPI
GmacIoPhyReset (
  UINT32   Id,
  BOOLEAN  Enable
  )
{
  switch (Id) {
    case 0:
      /* gpio4 RK_PB3, active low, shared with the switch reset */
      GpioPinWrite (4, GPIO_PIN_PB3, !Enable);
      break;
    default:
      break;
  }
}

VOID
EFIAPI
NorFspiEnableClock (
  UINT32  *CruBase
  )
{
  /* No FSPI flash on this board; nothing to clock. */
}

VOID
EFIAPI
I2cIomux (
  UINT32  id
  )
{
  switch (id) {
    case 0:
      /* i2c0m2 - RK8602/RK8603 CPU regulators */
      GpioPinSetFunction (0, GPIO_PIN_PD1, 3); // i2c0_scl_m2
      GpioPinSetFunction (0, GPIO_PIN_PD2, 3); // i2c0_sda_m2
      break;
    case 1:
      /* i2c1m2 - RK8602 NPU regulator (not managed by UEFI) */
      GpioPinSetFunction (0, GPIO_PIN_PD4, 9); // i2c1_scl_m2
      GpioPinSetFunction (0, GPIO_PIN_PD5, 9); // i2c1_sda_m2
      break;
    case 6:
      /* i2c6m0 - HYM8563 RTC */
      GpioPinSetFunction (0, GPIO_PIN_PD0, 9); // i2c6_scl_m0
      GpioPinSetFunction (0, GPIO_PIN_PC7, 9); // i2c6_sda_m0
      break;
    default:
      break;
  }
}

VOID
EFIAPI
UsbPortPowerEnable (
  VOID
  )
{
  DEBUG ((DEBUG_INFO, "UsbPortPowerEnable called\n"));

  /*
   * vcc5v0_host, active high (gpio4 RK_PB0). Feeds the USB2/USB3 host ports
   * through u2phy1_otg / u2phy2_host / u2phy3_host. The Type-C port's VBUS
   * (vcc5v0_usb) is always-on and has no enable GPIO.
   */
  GpioPinWrite (4, GPIO_PIN_PB0, TRUE);
  GpioPinSetDirection (4, GPIO_PIN_PB0, GPIO_PIN_OUTPUT);
}

VOID
EFIAPI
Usb2PhyResume (
  VOID
  )
{
  MmioWrite32 (0xfd5d0008, 0x20000000);
  MmioWrite32 (0xfd5d4008, 0x20000000);
  MmioWrite32 (0xfd5d8008, 0x20000000);
  MmioWrite32 (0xfd5dc008, 0x20000000);
  MmioWrite32 (0xfd7f0a10, 0x07000700);
  MmioWrite32 (0xfd7f0a10, 0x07000000);
}

VOID
EFIAPI
PcieIoInit (
  UINT32  Segment
  )
{
  /* Set reset and power IO to gpio output mode */
  switch (Segment) {
    case PCIE_SEGMENT_PCIE20L0: // AP6275P Wi-Fi on pcie2x1l0 / combphy1
      /* reset, active high: gpio1 RK_PB4 */
      GpioPinSetDirection (1, GPIO_PIN_PB4, GPIO_PIN_OUTPUT);
      break;
    /*
     * PCIE_SEGMENT_PCIE30X4 (the x4 controller) is deliberately not handled:
     * the connector that looks like M.2 is mSATA on SATA0 and the x4 lanes are
     * not routed. PcdPcie30Supported is FALSE.
     */
    default:
      break;
  }
}

VOID
EFIAPI
PciePowerEn (
  UINT32   Segment,
  BOOLEAN  Enable
  )
{
  /*
   * Nothing to switch: the Wi-Fi slot's 3V3 rail (vcc3v3_pcie30) is not
   * controlled by a GPIO - the device tree declares it always/boot-on and
   * carries no gpios property.
   */
}

VOID
EFIAPI
PciePeReset (
  UINT32   Segment,
  BOOLEAN  Enable
  )
{
  switch (Segment) {
    case PCIE_SEGMENT_PCIE20L0:
      GpioPinWrite (1, GPIO_PIN_PB4, !Enable);
      break;
    default:
      break;
  }
}

VOID
EFIAPI
HdmiTxIomux (
  IN UINT32  Id
  )
{
  switch (Id) {
    case 0:
      /* hdmim0 pin group, same defaults as the other RK3588 boards */
      GpioPinSetFunction (4, GPIO_PIN_PC1, 5); // hdmim0_tx0_cec
      GpioPinSetPull (4, GPIO_PIN_PC1, GPIO_PIN_PULL_NONE);
      GpioPinSetFunction (1, GPIO_PIN_PA5, 5); // hdmim0_tx0_hpd
      GpioPinSetPull (1, GPIO_PIN_PA5, GPIO_PIN_PULL_NONE);
      GpioPinSetFunction (4, GPIO_PIN_PB7, 5); // hdmim0_tx0_scl
      GpioPinSetPull (4, GPIO_PIN_PB7, GPIO_PIN_PULL_NONE);
      GpioPinSetFunction (4, GPIO_PIN_PC0, 5); // hdmim0_tx0_sda
      GpioPinSetPull (4, GPIO_PIN_PC0, GPIO_PIN_PULL_NONE);
      break;
  }
}

/*
 * On-board 4-pin fan on PWM15, which is controller 3 / channel 3 in this
 * firmware's numbering (pwm15 = pwm@febf0030 -> base 0xfebf0000, offset 0x30).
 * The device tree drives it with pwms = <&pwm15 0 1000000 0>, i.e. 1 kHz.
 */
PWM_DATA  pwm_data = {
  .ControllerID = PWM_CONTROLLER3,
  .ChannelID    = PWM_CHANNEL3,
  .PeriodNs     = 1000000,
  .DutyNs       = 500000,
  .Polarity     = FALSE,
}; // PWM15

VOID
EFIAPI
PwmFanIoSetup (
  VOID
  )
{
  GpioPinSetFunction (1, GPIO_PIN_PC6, 0xB); // PWM15_M2
  RkPwmSetConfig (&pwm_data);
  RkPwmEnable (&pwm_data);
}

VOID
EFIAPI
PwmFanSetSpeed (
  IN UINT32  Percentage
  )
{
  pwm_data.DutyNs = pwm_data.PeriodNs * Percentage / 100;
  RkPwmSetConfig (&pwm_data);
}

VOID
EFIAPI
PlatformInitLeds (
  VOID
  )
{
  /* work LED, active high: gpio3 RK_PB7 */
  GpioPinWrite (3, GPIO_PIN_PB7, FALSE);
  GpioPinSetDirection (3, GPIO_PIN_PB7, GPIO_PIN_OUTPUT);
}

VOID
EFIAPI
PlatformSetStatusLed (
  IN BOOLEAN  Enable
  )
{
  GpioPinWrite (3, GPIO_PIN_PB7, Enable);
}

CONST EFI_GUID *
EFIAPI
PlatformGetDtbFileGuid (
  IN UINT32  CompatMode
  )
{
  STATIC CONST EFI_GUID  VendorDtbFileGuid = {
    // DeviceTree/Vendor.inf
    0xd58b4028, 0x43d8, 0x4e97, { 0x87, 0xd4, 0x4e, 0x37, 0x16, 0x13, 0x65, 0x80 }
  };

  switch (CompatMode) {
    case FDT_COMPAT_MODE_VENDOR:
      return &VendorDtbFileGuid;
  }

  /* No mainline device tree for this board. */
  return NULL;
}

VOID
EFIAPI
PlatformEarlyInit (
  VOID
  )
{
  /*
   * HDMI0 enable, active high: gpio4 RK_PB1 (the device tree's
   * "enable-gpios" on &hdmi0). Raise it as early as possible: this board has
   * no serial console, so HDMI is the only way to see the firmware at all.
   * If HDMI stays dark, this pin is the first thing to check - try
   * GpioPinWrite(..., FALSE) if it turns out to be active low.
   */
  GpioPinWrite (4, GPIO_PIN_PB1, TRUE);
  GpioPinSetDirection (4, GPIO_PIN_PB1, GPIO_PIN_OUTPUT);
}
