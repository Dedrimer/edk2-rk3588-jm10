/** @file
 *
 *  HYM8563 real-time clock on I2C6.
 *
 *  The vendor device tree (rk3588-yjh-jm10.dts) puts the board's RTC on
 *  i2c6 at address 0x51:
 *
 *    hym8563: hym8563@51 {
 *      compatible = "haoyu,hym8563";
 *      reg = <0x51>;
 *      clock-frequency = <32768>;
 *      wakeup-source;
 *      interrupt-parent = <&gpio0>;
 *      interrupts = <RK_PB0 IRQ_TYPE_LEVEL_LOW>;
 *    };
 *
 *  This is the ACPI equivalent of that node. The _CID of "PRP0001" plus the
 *  "compatible" entry in _DSD let the OS match its ordinary (device-tree
 *  style) hym8563 driver against an ACPI-enumerated device, which is the
 *  usual ACPI-on-ARM idiom for a part that has no ACPI hardware ID.
 *
 *  Copyright (c) 2026, Yijiahe JM10 port
 *
 *  SPDX-License-Identifier: BSD-2-Clause-Patent
 *
 **/
#include "AcpiTables.h"

  Device (RTC0) {
    Name (_HID, "RKCP8563")
    Name (_CID, "PRP0001")
    Name (_UID, 0x0)
    Name (_CCA, 0x0)

    Method (_CRS, 0x0, Serialized) {
      Name (RBUF, ResourceTemplate() {
        // 0x51 on i2c6, 100 kHz.
        I2cSerialBusV2 (0x0051, ControllerInitiated, 0x000186A0,
          AddressingMode7Bit, "\\_SB.I2C6",
          0x00, ResourceConsumer, , Exclusive)
        // HYM8563_INT -> gpio0 RK_PB0 (GPIO0_B0), level low, pull up.
        GpioInt (Level, ActiveLow, Shared, PullUp, 0x0000,
          "\\_SB.GPI0", 0x00, ResourceConsumer)
        {
          GPIO_PIN_PB0
        }
      })
      Return (RBUF)
    }

    Name (_DSD, Package () {
      ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
      Package () {
        Package (2) { "compatible", "haoyu,hym8563" },
        Package (2) { "clock-frequency", 32768 },
        Package (2) { "wakeup-source", 1 },
      }
    })
  }
