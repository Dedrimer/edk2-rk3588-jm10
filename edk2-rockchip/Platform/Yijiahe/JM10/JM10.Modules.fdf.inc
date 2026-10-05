## @file
#
#  Copyright (c) 2026, Yijiahe JM10 port
#
#  SPDX-License-Identifier: BSD-2-Clause-Patent
#
##

  # ACPI Support
  #
  # This platform is ACPI-only - there is deliberately no DeviceTree/ module
  # here. See the header of AcpiTables/Dsdt.asl for what that means for the
  # board's MV88E6190 switch.
  INF RuleOverride = ACPITABLE $(PLATFORM_DIRECTORY)/AcpiTables/AcpiTables.inf
