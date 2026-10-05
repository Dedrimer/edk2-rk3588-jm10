# Rockchip Vendor BSP Device Trees
## Sources
* <https://github.com/armbian/linux-rockchip/tree/f3fb30ac9de06b41fb621d17bc53603f1f48ac90/arch/arm64/boot/dts/rockchip>
  * Updated to `rk-6.1-rkr1` branch, currently called `vendor` branch in armbian/build

* roc-rk3588s-pc: <https://gitlab.com/firefly-linux/kernel/-/tree/b8646da2122f45a2c02082d949427b80d2e89b1f/arch/arm64/boot/dts/rockchip>

* itx-3588j: <https://gitlab.com/firefly-linux/kernel/-/tree/e14c28295dd7ee8f807899e9b0b7da5f79742e4f/arch/arm64/boot/dts/rockchip>
  (note: in the dtb given here, the builtin bootargs in the source above were commented out
   before building. Not sure if that was a necessary step - SS)

* rk3588-firefly-aio-3588q: <https://gitlab.com/firefly-linux/kernel/-/tree/fa0e053fd911339b825407cb6d4b167fad7cdc49/arch/arm64/boot/dts/rockchip>

* rk3588-rock-5b-plus: <https://github.com/radxa/kernel/blob/3b95df6d8bf567857b69e5266f1cb0651a6cfb3e/arch/arm64/boot/dts/rockchip/>

* rk3588s-fydetab-duo: <https://github.com/Linux-for-Fydetab-Duo/linux-rockchip/tree/14294048d2a0deb7f38c890329aded87038d3299/arch/arm64/boot/dts/rockchip>
  (note: dtb taken from the `noble` branch which is based on the rockchip 6.1 rkr3 bsp kernel)

* rk3588-yjh-jm10 (Yijiahe JM10-3588): taken from the `armbian-build-jm10` tree
  (<https://github.com/armbian/build>-based), which builds it from
  `userpatches/kernel/rockchip-6.1-yjh-jm10/` on top of the same
  `armbian/linux-rockchip` `vendor` (rk-6.1-rkr) branch as the first entry above.
  It is byte-identical to the DTB the board currently boots with, so the OS sees
  the same MV88E6190 DSA topology under UEFI as it does under U-Boot.
  (md5 f51e925c7659394944920dc99fe54a4d)

## License
SPDX-License-Identifier: GPL-2.0-only
