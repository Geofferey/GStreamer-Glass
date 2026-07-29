# SPDX-License-Identifier: AGPL-3.0-only

# The Network tab is intentionally empty. It previously let the app modify
# Windows network configuration directly (adapter offload settings, power
# management, QoS/DSCP policy, a recovery snapshot + scheduled task to undo
# changes if the app didn't exit cleanly). That entire mechanism has been
# removed -- this file, the tab, and its sidebar entry are kept as a
# placeholder for whatever comes next, not as a shell around dead code.
