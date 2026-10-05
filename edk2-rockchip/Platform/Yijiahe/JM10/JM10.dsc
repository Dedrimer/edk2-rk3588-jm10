## @file
#
#  Yijiahe JM10-3588 (RK3588) - ACPI-only platform.
#
#  The board is described entirely with ACPI tables (AcpiTables/Dsdt.asl and
#  its includes); no device tree is embedded in the firmware or published to
#  the OS. The translation of the vendor device tree that the OS image is
#  built with (armbian-build-jm10, userpatches/kernel/rockchip-6.1-yjh-jm10)
#  lives in AcpiTables/Dsdt.asl, which also lists what ACPI cannot express.
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

  # Ethernet is present but is not driven from the firmware: seven RJ45 ports
  # hang off a Marvell MV88E6190 DSA switch whose CPU port is wired to GMAC0
  # over a fixed 1000 Mbit RGMII link. There is no UEFI driver for the switch,
  # and bringing up the MAC alone does not help - the switch leaves reset with
  # every port disabled and an empty VLAN table, and nothing forwards until it
  # is programmed.
  #
  # On top of that, Linux's DSA framework is device-tree only, so the switch
  # topology cannot be represented in the ACPI tables either (see the note in
  # AcpiTables/Dsdt.asl). The MAC itself is still described by Gmac0.asl so the
  # OS knows the controller exists; the seven ports are not usable this way.
  #
  # Flip this to TRUE together with PcdGmac0Supported to also have the firmware
  # poke the MAC/MDIO and the shared switch reset line (GPIO4_B3).
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

  # GMAC PCDs are omitted because RK3588_GMAC_ENABLE is FALSE above - without
  # the UEFI driver the delays would have nothing to program them into. The
  # MAC is still described to the OS through Gmac0.asl. To bring it up inside
  # UEFI (to debug the link towards the switch), set RK3588_GMAC_ENABLE = TRUE
  # and uncomment these; tx_delay is from the device tree, and gmac1 is only a
  # guess, since the vendor device tree wires the switch to gmac0 alone:
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
  # I2S0 drives the RT5651 codec that sits on I2C7. The codec node itself is
  # board specific and lives in AcpiTables/Rt5651.asl; this flag only controls
  # whether the shared I2S0 device (I2s.asl) is emitted.
  #
  gRK3588TokenSpaceGuid.PcdI2S0Supported|TRUE

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
  # ACPI only. The board used to publish the vendor device tree because the
  # MV88E6190 switch is only ever driven through it (Linux mv88e6xxx/DSA); with
  # the board now described by the ACPI tables in AcpiTables/, the device tree
  # is neither embedded in the firmware (there is no DeviceTree/ module below)
  # nor published, so the OS is handed ACPI and nothing else.
  #
  # Ethernet is the one casualty of that decision and it is unavoidable: DSA
  # cannot be described in ACPI. See the header of AcpiTables/Dsdt.asl.
  #
  gRK3588TokenSpaceGuid.PcdConfigTableModeDefault|$(CONFIG_TABLE_MODE_ACPI)

################################################################################
#
# Components Section - list of all EDK II Modules needed by this Platform.
#
################################################################################
[Components.common]
  # ACPI Support
  $(PLATFORM_DIRECTORY)/AcpiTables/AcpiTables.inf
