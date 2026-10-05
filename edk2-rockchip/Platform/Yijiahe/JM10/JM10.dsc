## @file
#
#  Copyright (c) 2026, Yijiahe JM10 port
#
#  SPDX-License-Identifier: BSD-2-Clause-Patent
#
##

################################################################################
#
# Defines Section - statements that will be processed to create a Makefile.
#
################################################################################
[Defines]
  PLATFORM_NAME                  = JM10
  PLATFORM_VENDOR                = Yijiahe
  PLATFORM_GUID                  = 832247ce-1f57-487a-ac59-d5f8f3d4551d
  PLATFORM_VERSION               = 0.1
  DSC_SPECIFICATION              = 0x00010019
  OUTPUT_DIRECTORY               = Build/$(PLATFORM_NAME)
  VENDOR_DIRECTORY               = Platform/$(PLATFORM_VENDOR)
  PLATFORM_DIRECTORY             = $(VENDOR_DIRECTORY)/$(PLATFORM_NAME)
  SUPPORTED_ARCHITECTURES        = AARCH64
  BUILD_TARGETS                  = DEBUG|RELEASE
  SKUID_IDENTIFIER               = DEFAULT
  FLASH_DEFINITION               = Silicon/Rockchip/RK3588/RK3588.fdf
  RK_PLATFORM_FVMAIN_MODULES     = $(PLATFORM_DIRECTORY)/$(PLATFORM_NAME).Modules.fdf.inc

  # The board has no SD card slot (eMMC + mSATA only).
  DEFINE RK_SD_ENABLE = FALSE

  # The board has no SPI NOR flash either. Without NorFlashDxe the variable
  # store comes from the FIT 'nvdata' region on the boot device (see the
  # comment above RK_NOR_FLASH_ENABLE in Silicon/Rockchip/FvMainModules.fdf.inc:
  # RkFvbDxe has no hard dependency on NorFlashDxe).
  DEFINE RK_NOR_FLASH_ENABLE = FALSE

  # Ethernet: seven RJ45 ports hang off a Marvell MV88E6190 DSA switch, whose
  # two CPU ports are wired to GMAC0 (rgmii) and - unconfirmed - GMAC1. There is
  # no UEFI driver for the switch, and bringing up the MAC alone does not help:
  # the switch comes out of reset with every port disabled and an empty VLAN
  # table, and nothing forwards until it is programmed.
  #
  # Rather than have the firmware poke the MAC/MDIO (and the switch reset line
  # on GPIO4_B3) for no benefit, leave the whole path to the OS, which drives
  # the switch through Linux's mv88e6xxx/DSA driver. Consequence: no UEFI-side
  # networking (no PXE/HTTP boot), which is fine because this board boots from
  # local storage (eMMC firmware + mSATA OS).
  #
  # Flip this to TRUE together with PcdGmac0Supported if the MAC is ever wanted
  # inside UEFI.
  DEFINE RK3588_GMAC_ENABLE = FALSE

  #
  # HYM8563 RTC support
  # I2C location configured by PCDs below.
  #
  DEFINE RK_RTC8563_ENABLE = TRUE

  #
  # RK3588-based platform
  #
!include Silicon/Rockchip/RK3588/RK3588Platform.dsc.inc

################################################################################
#
# Library Class section - list of all Library Classes needed by this Platform.
#
################################################################################

[LibraryClasses.common]
  RockchipPlatformLib|$(PLATFORM_DIRECTORY)/Library/RockchipPlatformLib/RockchipPlatformLib.inf

################################################################################
#
# Pcd Section - list of all EDK II PCD Entries defined by this Platform.
#
################################################################################

[PcdsFixedAtBuild.common]
  # SMBIOS platform config
  gRockchipTokenSpaceGuid.PcdPlatformName|"JM10-3588"
  gRockchipTokenSpaceGuid.PcdPlatformVendorName|"Yijiahe"
  gRockchipTokenSpaceGuid.PcdFamilyName|"JM10"
  gRockchipTokenSpaceGuid.PcdDeviceTreeName|"rk3588-yjh-jm10"

  # I2C
  #   bus 0: RK8602 @0x42 (vdd_cpu_big0) + RK8603 @0x43 (vdd_cpu_big1)
  #   bus 6: HYM8563 RTC @0x51
  gRockchipTokenSpaceGuid.PcdI2cSlaveAddresses|{ 0x42, 0x43, 0x51 }
  gRockchipTokenSpaceGuid.PcdI2cSlaveBuses|{ 0x0, 0x0, 0x6 }
  gRockchipTokenSpaceGuid.PcdI2cSlaveBusesRuntimeSupport|{ FALSE, FALSE, TRUE }
  gRockchipTokenSpaceGuid.PcdRk860xRegulatorAddresses|{ 0x42, 0x43 }
  gRockchipTokenSpaceGuid.PcdRk860xRegulatorBuses|{ 0x0, 0x0 }
  gRockchipTokenSpaceGuid.PcdRk860xRegulatorTags|{ $(SCMI_CLK_CPUB01), $(SCMI_CLK_CPUB23) }
  gPcf8563RealTimeClockLibTokenSpaceGuid.PcdI2cSlaveAddress|0x51
  gRockchipTokenSpaceGuid.PcdRtc8563Bus|0x6

  # eMMC is HS400 with enhanced strobe (200 MHz) on this board, so deliberately
  # do NOT copy the "PcdDwcSdhciDisableHs400|TRUE" workaround some other boards
  # need.

  # GMAC PCDs are omitted because RK3588_GMAC_ENABLE is FALSE above. To
  # experiment with UEFI-side networking, set RK3588_GMAC_ENABLE = TRUE and
  # uncomment the following (tx_delay from the device tree; gmac1 is only a
  # guess - the board appears to have a second CPU link to the switch, but the
  # vendor device tree only describes gmac0):
  # gRK3588TokenSpaceGuid.PcdGmac0Supported|TRUE
  # gRK3588TokenSpaceGuid.PcdGmac0TxDelay|0x45
  # gRK3588TokenSpaceGuid.PcdGmac0RxDelay|0x00
  # gRK3588TokenSpaceGuid.PcdGmac1Supported|TRUE
  # gRK3588TokenSpaceGuid.PcdGmac1TxDelay|0x42
  # gRK3588TokenSpaceGuid.PcdGmac1RxDelay|0x00

  #
  # PCIe/SATA/USB Combo PIPE PHY - hard-wired on this board, not switchable.
  #   combphy0_ps  -> SATA0   (the "M.2" slot is in fact mSATA)
  #   combphy1_ps  -> PCIE2x1 (pcie2x1l0, onboard AP6275P Wi-Fi)
  #   combphy2_psu -> USB3    (usbhost3_0 / fcd00000)
  #
  gRK3588TokenSpaceGuid.PcdComboPhy0Switchable|FALSE
  gRK3588TokenSpaceGuid.PcdComboPhy1Switchable|FALSE
  gRK3588TokenSpaceGuid.PcdComboPhy2Switchable|FALSE
  gRK3588TokenSpaceGuid.PcdComboPhy0ModeDefault|$(COMBO_PHY_MODE_SATA)
  gRK3588TokenSpaceGuid.PcdComboPhy1ModeDefault|$(COMBO_PHY_MODE_PCIE)
  gRK3588TokenSpaceGuid.PcdComboPhy2ModeDefault|$(COMBO_PHY_MODE_USB3)

  #
  # PCI Express 3.0
  # The x4 controller (fe150000) is not routed to anything on this board; the
  # slot that looks like M.2 is mSATA on SATA0. Keep it disabled.
  #
  gRK3588TokenSpaceGuid.PcdPcie30Supported|FALSE

  #
  # USB/DP Combo PHY - lane mux values mirror rockchip,dp-lane-mux = <2 3>
  # in the vendor device tree.
  #
  gRK3588TokenSpaceGuid.PcdUsbDpPhy0Supported|TRUE
  gRK3588TokenSpaceGuid.PcdUsbDpPhy1Supported|TRUE
  gRK3588TokenSpaceGuid.PcdDp0LaneMux|{ 0x2, 0x3 }
  gRK3588TokenSpaceGuid.PcdDp1LaneMux|{ 0x2, 0x3 }

  #
  # On-board 4-pin PWM fan on PWM15 (controller 3 / channel 3, pin GPIO1_C6).
  #
  gRK3588TokenSpaceGuid.PcdHasOnBoardFanOutput|TRUE

  #
  # Display: HDMI0 on the HDMI connector, DP0 on the Type-C port (USB-C
  # DisplayPort alt-mode, one cable orientation only - a firmware-wide
  # limitation, not board specific). DP1 is left out because no DP1 connector
  # could be identified on the board; add VOP_OUTPUT_IF_DP1 if that turns out
  # to be wrong.
  #
  gRK3588TokenSpaceGuid.PcdDisplayConnectors|{CODE({
    VOP_OUTPUT_IF_HDMI0,
    VOP_OUTPUT_IF_DP0
  })}

  #
  # ACPI / Device Tree mode.
  #
  # Default is ACPI+FDT ("both"), but Linux prefers ACPI when both tables are
  # present, and the MV88E6190 switch is only ever driven through the device
  # tree (Linux mv88e6xxx/DSA). Publish the device tree only, so the OS sees
  # exactly the same DTB it does today.
  #
  gRK3588TokenSpaceGuid.PcdConfigTableModeDefault|$(CONFIG_TABLE_MODE_FDT)

  # Vendor DTB only - this board has no mainline device tree.
  gRK3588TokenSpaceGuid.PcdFdtCompatModeDefault|$(FDT_COMPAT_MODE_VENDOR)

################################################################################
#
# Components Section - list of all EDK II Modules needed by this Platform.
#
################################################################################
[Components.common]
  # ACPI Support
  $(PLATFORM_DIRECTORY)/AcpiTables/AcpiTables.inf

  # Device Tree Support
  $(PLATFORM_DIRECTORY)/DeviceTree/Vendor.inf
