/** @file
 *
 *  Realtek RT5651 audio codec on I2C7.
 *
 *  The vendor device tree (rk3588-yjh-jm10.dts) describes the board's only
 *  analogue audio path as I2S0 (i2s@fe470000) feeding an RT5651 codec on
 *  i2c7 at address 0x1a, with the headphone-detect line on gpio1 RK_PD5:
 *
 *    &i2c7 {
 *      rt5651: rt5651@1a {
 *        compatible = "rockchip,rt5651";
 *        reg = <0x1a>;
 *        clock-names = "mclk";
 *        clocks = <&cru I2S0_8CH_MCLKOUT>;
 *      };
 *    };
 *
 *    &i2s0_8ch { status = "okay"; };
 *
 *    rt5651_sound {
 *      simple-audio-card,hp-det-gpio = <&gpio1 RK_PD5 GPIO_ACTIVE_LOW>;
 *      ...
 *    };
 *
 *  This is the ACPI equivalent of the codec node. The I2S0 CPU DAI itself
 *  comes from I2s.asl (gated on PcdI2S0Supported in JM10.dsc); only the
 *  codec is board specific and therefore lives here.
 *
 *  Note on "compatible": the vendor tree wrote "rockchip,rt5651", which is
 *  not the upstream binding (upstream is "realtek,rt5651"). Both are
 *  advertised here so that either driver binds.
 *
 *  Note on audio as a whole: the ASoC machine link that ties codec and CPU
 *  DAI together (simple-audio-card) is a device-tree construct with no ACPI
 *  equivalent, so the OS still needs its own ACPI glue to bring the card up.
 *  The codec and I2S controller are described because they are real board
 *  hardware, not because that alone makes sound work.
 *
 *  Copyright (c) 2026, Yijiahe JM10 port
 *
 *  SPDX-License-Identifier: BSD-2-Clause-Patent
 *
 **/
#include "AcpiTables.h"

  Device (AUD0) {
    Name (_HID, "RKCP5651")
    Name (_CID, "PRP0001")
    Name (_UID, 0x0)
    Name (_CCA, 0x0)

    Method (_CRS, 0x0, Serialized) {
      Name (RBUF, ResourceTemplate() {
        // 0x1a on i2c7, 400 kHz.
        I2cSerialBusV2 (0x001A, ControllerInitiated, 0x00061A80,
          AddressingMode7Bit, "\\_SB.I2C7",
          0x00, ResourceConsumer, , Exclusive)
        // Headphone detect -> gpio1 RK_PD5 (GPIO1_D5), active low.
        GpioInt (Edge, ActiveLow, Exclusive, PullNone, 0x0000,
          "\\_SB.GPI1", 0x00, ResourceConsumer)
        {
          GPIO_PIN_PD5
        }
      })
      Return (RBUF)
    }

    Name (_DSD, Package () {
      ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
      Package () {
        Package (2) { "compatible", Package () { "realtek,rt5651", "rockchip,rt5651" } },
        Package (2) { "clock-names", "mclk" },
        Package (2) { "assigned-clock-rates", 1050000 },
      }
    })
  }
