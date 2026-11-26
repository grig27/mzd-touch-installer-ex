#!/bin/sh
# install.sh -- install Android Auto touch, boot autorun and TouchTune.
#
# The Android Auto transaction runs first and is finalized (rootfs read-only,
# watchdog re-enabled). Boot autorun is its own transaction after that.
# TouchTune then owns the single final SafeReboot when it changes something.
# See lib/combined.sh.
#
# Copyright (C) 2026 caeptncrack
# SPDX-License-Identifier: GPL-3.0-or-later

BASE=${1:-$(cd "$(dirname "$0")/.." && pwd)}
MZD_STICK="$BASE"
export MZD_STICK
. "$BASE/lib/mzd-safety.sh" || exit 1
. "$BASE/lib/aa-touch.sh" || exit 2
. "$BASE/lib/xx74.sh" || exit 3
. "$BASE/lib/combined.sh" || exit 4
mzd_install_traps
combined_install
rc=$?
# The last message tells the user when the stick may be pulled.
mzd_popup_final
exit "$rc"
