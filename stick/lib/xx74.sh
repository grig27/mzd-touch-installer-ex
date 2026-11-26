#!/bin/sh
# xx74.sh -- boot autorun for Mazda Connect 74.00.324 / 74.00.324A.
#
# Installs /data_persist/dev/bin/autorun and a marked block at the end of the
# startup scripts that exist on this car. The block only starts that file.
# Originals are backed up under /data_persist/mzd-xx74/backups before the
# first write; removal restores those bytes. Nothing here disables the
# watchdog, starts run.sh, or executes a command taken from a USB file.
#
# The backup helpers in mzd-safety.sh are reused with MZD_BACKUP_ROOT pointed
# at this part's own directory for the duration of a call. Callers must source
# this file before lib/combined.sh.
#
# Copyright (C) 2026 caeptncrack
# SPDX-License-Identifier: GPL-3.0-or-later

[ -n "${MZD_XX74_LOADED:-}" ] && return 0
MZD_XX74_LOADED=1

MZD_XX_DIR="$MZD_DATA/mzd-xx74"
MZD_XX_BACKUP_ROOT="$MZD_XX_DIR/backups"
MZD_XX_STATE="$MZD_XX_DIR/install-state"
MZD_XX_AUTORUN="$MZD_DATA/dev/bin/autorun"
MZD_XX_STICK_AUTORUN="$MZD_STICK/xx74/autorun"
MZD_XX_NAMES="start-normal-scripts start-normal-bin emmc-mount"
XX74_CHANGED=0

# ---------------------------------------------------------------------------
# Paths and the hook block
# ---------------------------------------------------------------------------

xx74_path() {
    case "$1" in
        start-normal-scripts) printf '%s\n' "$MZD_ROOT/jci/scripts/start_normal_mode.sh" ;;
        start-normal-bin) printf '%s\n' "$MZD_ROOT/jci/bin/start_normal_mode.sh" ;;
        emmc-mount) printf '%s\n' "$MZD_ROOT/usr/sbin/emmc_mount_data_persist.sh" ;;
        *) return 1 ;;
    esac
}

xx74_write_hook() {
    printf '%s\n' \
        '# mzd-xx74 begin' \
        'if [ -e /data_persist/dev/bin/autorun ]; then' \
        '    /data_persist/dev/bin/autorun &' \
        'fi' \
        '# mzd-xx74 end' >"$1"
}

xx74_ends_with_newline() {
    tail -c 1 "$1" 2>/dev/null | grep -q '^$'
}

# 0 when the file ends with exactly one copy of our hook block.
xx74_hook_exact() {
    local exp got
    exp="$MZD_ROOT/tmp/xx74-hook-exp.$$"
    got="$MZD_ROOT/tmp/xx74-hook-got.$$"
    mkdir -p "$MZD_ROOT/tmp" || return 1
    xx74_write_hook "$exp" || { rm -f "$exp" "$got"; return 1; }
    tail -n 5 "$1" >"$got" 2>/dev/null || { rm -f "$exp" "$got"; return 1; }
    if [ "$(mzd_sha256_file "$exp")" = "$(mzd_sha256_file "$got")" ]; then
        rm -f "$exp" "$got"
        return 0
    fi
    rm -f "$exp" "$got"
    return 1
}

# stock | hooked | foreign | broken | symlink
xx74_class() {
    local file="$1" begin end
    if [ -L "$file" ] || { [ -e "$file" ] && [ ! -f "$file" ]; }; then
        printf 'symlink\n'
        return 0
    fi
    [ -f "$file" ] || { printf 'absent\n'; return 0; }
    begin=$(mzd_count_line "$file" '# mzd-xx74 begin')
    end=$(mzd_count_line "$file" '# mzd-xx74 end')
    if [ "$begin" = 1 ] && [ "$end" = 1 ] && xx74_hook_exact "$file"; then
        printf 'hooked\n'
        return 0
    fi
    if [ "$begin" != 0 ] || [ "$end" != 0 ]; then
        printf 'broken\n'
        return 0
    fi
    if grep -q -F '/data_persist/dev/bin/autorun' "$file" 2>/dev/null || \
       grep -q -F '/mnt/data_persist/dev/bin/autorun' "$file" 2>/dev/null; then
        printf 'foreign\n'
        return 0
    fi
    printf 'stock\n'
}

xx74_autorun_sha() {
    mzd_sha256_file "$MZD_XX_STICK_AUTORUN"
}

# absent | ours | other | symlink
xx74_autorun_class() {
    local want got
    if [ ! -e "$MZD_XX_AUTORUN" ] && [ ! -L "$MZD_XX_AUTORUN" ]; then
        printf 'absent\n'
        return 0
    fi
    if [ -L "$MZD_XX_AUTORUN" ] || [ ! -f "$MZD_XX_AUTORUN" ]; then
        printf 'symlink\n'
        return 0
    fi
    want=$(xx74_autorun_sha) || { printf 'other\n'; return 0; }
    got=$(mzd_sha256_file "$MZD_XX_AUTORUN") || { printf 'other\n'; return 0; }
    if [ "$got" = "$want" ]; then
        printf 'ours\n'
    else
        printf 'other\n'
    fi
}

xx74_payload_ok() {
    mzd_real_file "$MZD_XX_STICK_AUTORUN" || {
        mzd_error "boot autorun payload missing: xx74/autorun"
        return 1
    }
    mzd_real_file "$MZD_STICK/xx74/SOURCE.txt" || {
        mzd_error "boot autorun payload missing: xx74/SOURCE.txt"
        return 1
    }
    return 0
}

# Names of the startup scripts that exist, space separated (global XX74_PRESENT).
xx74_collect_present() {
    local name path
    XX74_PRESENT=""
    XX74_SYMLINK=0
    for name in $MZD_XX_NAMES; do
        path=$(xx74_path "$name") || return 1
        if [ -L "$path" ]; then
            XX74_SYMLINK=1
            continue
        fi
        if [ -f "$path" ]; then
            XX74_PRESENT="$XX74_PRESENT $name"
        fi
    done
    XX74_PRESENT=${XX74_PRESENT# }
    return 0
}

# ---------------------------------------------------------------------------
# Backup root for this part only
# ---------------------------------------------------------------------------

xx74_enter() {
    XX74_SAVED_BACKUP_ROOT=$MZD_BACKUP_ROOT
    XX74_SAVED_BACKUP_DIR=$MZD_BACKUP_DIR
    XX74_SAVED_BACKUP_PREFER=$MZD_BACKUP_PREFER
    MZD_BACKUP_ROOT=$MZD_XX_BACKUP_ROOT
    MZD_BACKUP_DIR=""
    MZD_BACKUP_PREFER=""
}

xx74_leave() {
    MZD_BACKUP_ROOT=$XX74_SAVED_BACKUP_ROOT
    MZD_BACKUP_DIR=$XX74_SAVED_BACKUP_DIR
    MZD_BACKUP_PREFER=$XX74_SAVED_BACKUP_PREFER
}

xx74_state_files() {
    [ -f "$MZD_XX_STATE" ] || return 1
    awk -F= '$1 == "file" && $2 != "" { print $2 }' "$MZD_XX_STATE"
}

xx74_state_value() {
    [ -f "$MZD_XX_STATE" ] || return 1
    awk -F= -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }' "$MZD_XX_STATE"
}

# Strip our hook and print a hash. Fails when the tail is not our exact block.
xx74_stripped_hash() {
    local file="$1" tmp
    xx74_hook_exact "$file" || return 1
    tmp="$MZD_ROOT/tmp/xx74-strip.$$"
    mkdir -p "$MZD_ROOT/tmp" || return 1
    awk '
        $0 == "# mzd-xx74 begin" { skip = 1; next }
        $0 == "# mzd-xx74 end" { skip = 0; next }
        skip != 1 { print }
    ' "$file" >"$tmp" || { rm -f "$tmp"; return 1; }
    mzd_sha256_file "$tmp"
    local rc=$?
    rm -f "$tmp"
    return "$rc"
}

# 0 when every hooked live file matches the backup byte for byte outside the hook.
xx74_backup_matches_live() {
    local name path live_hash orig_hash listed have
    [ -n "$MZD_BACKUP_DIR" ] || return 1
    xx74_collect_present || return 1
    [ -n "$XX74_PRESENT" ] || return 1
    for name in $XX74_PRESENT; do
        path=$(xx74_path "$name") || return 1
        [ "$(xx74_class "$path")" = hooked ] || return 1
        mzd_real_file "$MZD_BACKUP_DIR/$name" || return 1
        live_hash=$(xx74_stripped_hash "$path") || return 1
        orig_hash=$(mzd_sha256_file "$MZD_BACKUP_DIR/$name") || return 1
        [ "$live_hash" = "$orig_hash" ] || return 1
    done
    for name in $(xx74_state_files); do
        case " $XX74_PRESENT " in
            *" $name "*) ;;
            *) return 1 ;;
        esac
    done
    for name in $XX74_PRESENT; do
        listed=0
        for have in $(xx74_state_files); do
            [ "$have" = "$name" ] && listed=1
        done
        [ "$listed" = 1 ] || return 1
    done
    return 0
}

xx74_load_backup() {
    local prefer
    MZD_BACKUP_DIR=""
    MZD_BACKUP_PREFER=""
    prefer=$(xx74_state_value backup 2>/dev/null || true)
    case "$prefer" in
        ''|*/*|.*) ;;
        *) MZD_BACKUP_PREFER=$prefer ;;
    esac
    mzd_backup_find xx74-
}

# missing | clean | ours | partial | foreign
xx74_state_inner() {
    local auto any_foreign any_hooked any_stock any_other name path class recorded
    xx74_collect_present || { printf 'foreign\n'; return 0; }
    if [ "$XX74_SYMLINK" = 1 ]; then
        printf 'foreign\n'
        return 0
    fi
    if [ -z "$XX74_PRESENT" ]; then
        if [ -f "$MZD_XX_STATE" ] || [ -e "$MZD_XX_AUTORUN" ] || [ -L "$MZD_XX_AUTORUN" ]; then
            printf 'partial\n'
        else
            printf 'missing\n'
        fi
        return 0
    fi
    any_foreign=0
    any_hooked=0
    any_stock=0
    any_other=0
    for name in $XX74_PRESENT; do
        path=$(xx74_path "$name") || { printf 'foreign\n'; return 0; }
        class=$(xx74_class "$path")
        case "$class" in
            foreign|symlink) any_foreign=1 ;;
            hooked) any_hooked=1 ;;
            stock) any_stock=1 ;;
            *) any_other=1 ;;
        esac
    done
    auto=$(xx74_autorun_class)
    if [ "$any_foreign" = 1 ] || [ "$auto" = symlink ]; then
        printf 'foreign\n'
        return 0
    fi
    if [ "$auto" = other ] && [ "$any_hooked" = 0 ] && [ ! -f "$MZD_XX_STATE" ]; then
        printf 'foreign\n'
        return 0
    fi
    if [ "$any_other" = 0 ] && [ "$any_hooked" = 0 ] && [ "$any_stock" = 1 ] && \
       [ "$auto" = absent ] && [ ! -f "$MZD_XX_STATE" ]; then
        printf 'clean\n'
        return 0
    fi
    if [ "$any_other" = 0 ] && [ "$any_stock" = 0 ] && [ "$any_hooked" = 1 ] && \
       [ "$auto" = ours ] && [ -f "$MZD_XX_STATE" ]; then
        recorded=$(xx74_state_value autorun 2>/dev/null || true)
        if [ "$recorded" = "$(xx74_autorun_sha)" ] && \
           grep -q '^format=mzd-xx74-v1$' "$MZD_XX_STATE" 2>/dev/null && \
           xx74_load_backup && xx74_backup_matches_live; then
            printf 'ours\n'
            return 0
        fi
    fi
    printf 'partial\n'
}

xx74_state() {
    local saved_root saved_dir saved_prefer result
    saved_root=$MZD_BACKUP_ROOT
    saved_dir=$MZD_BACKUP_DIR
    saved_prefer=$MZD_BACKUP_PREFER
    MZD_BACKUP_ROOT=$MZD_XX_BACKUP_ROOT
    MZD_BACKUP_DIR=""
    MZD_BACKUP_PREFER=""
    result=$(xx74_state_inner) || result=foreign
    MZD_BACKUP_ROOT=$saved_root
    MZD_BACKUP_DIR=$saved_dir
    MZD_BACKUP_PREFER=$saved_prefer
    printf '%s\n' "$result"
}

xx74_label() {
    case "$1" in
        clean) printf 'not installed\n' ;;
        ours) printf 'installed\n' ;;
        partial) printf 'partially installed\n' ;;
        missing) printf 'startup scripts missing\n' ;;
        foreign) printf 'modified by another installer\n' ;;
        *) printf 'unknown state\n' ;;
    esac
}

# ---------------------------------------------------------------------------
# Compose, publish, roll back
# ---------------------------------------------------------------------------

xx74_compose() {
    local original="$1" dest="$2" stripped
    xx74_ends_with_newline "$original" || {
        mzd_error "startup script has no final newline: $original"
        return 1
    }
    cp "$original" "$dest" || return 1
    # The backup copy is mode 0444. A plain cp keeps that, and the append
    # below would then be refused.
    chmod u+w "$dest" || return 1
    xx74_write_hook "$MZD_ROOT/tmp/xx74-hook-block.$$" || return 1
    cat "$MZD_ROOT/tmp/xx74-hook-block.$$" >>"$dest" || return 1
    rm -f "$MZD_ROOT/tmp/xx74-hook-block.$$"
    xx74_hook_exact "$dest" || {
        mzd_error "composed startup script does not end with the hook"
        return 1
    }
    stripped=$(xx74_stripped_hash "$dest") || return 1
    [ "$stripped" = "$(mzd_sha256_file "$original")" ] || {
        mzd_error "hook does not round-trip to the original file"
        return 1
    }
    return 0
}

xx74_apply_name() {
    local name="$1" src dest tmp sha
    src="$MZD_BACKUP_DIR/$name"
    dest=$(xx74_path "$name") || return 1
    mzd_require_file "$src" || return 1
    tmp="$MZD_ROOT/tmp/xx74-composed-$name"
    xx74_compose "$src" "$tmp" || return 1
    sha=$(mzd_sha256_file "$tmp") || { rm -f "$tmp"; return 1; }
    if ! mzd_stage_copy "$tmp" "$dest" "$sha"; then
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
    mzd_publish_staged "$dest" "$sha" || return 1
    XX74_APPLIED="$XX74_APPLIED $name"
    mzd_log "boot autorun hook verified: $name"
    return 0
}

xx74_rollback_install() {
    local name dest rec sha failures=0
    mzd_log "rolling back the boot autorun installation"
    for name in $XX74_APPLIED; do
        dest=$(xx74_path "$name") || { failures=1; continue; }
        if ! mzd_backup_restore_stage "$name" "$dest"; then
            failures=1
            continue
        fi
        rec=$(mzd_backup_record "$name") || { failures=1; continue; }
        sha=${rec%%|*}
        mzd_publish_staged "$dest" "$sha" || failures=1
        if grep -q -F '# mzd-xx74 begin' "$dest" 2>/dev/null; then
            mzd_error "rollback: hook still present in $name"
            failures=1
        fi
    done
    if [ "${XX74_AUTORUN_PREV:-0}" = 1 ] && [ -f "$MZD_XX_DIR/.autorun.rollback" ]; then
        mv -f "$MZD_XX_DIR/.autorun.rollback" "$MZD_XX_AUTORUN" || failures=1
    elif [ "${XX74_WROTE_AUTORUN:-0}" = 1 ]; then
        rm -f "$MZD_XX_AUTORUN" || failures=1
    fi
    if [ "${XX74_STATE_PREV:-0}" = 1 ] && [ -f "$MZD_XX_DIR/.state.rollback" ]; then
        mv -f "$MZD_XX_DIR/.state.rollback" "$MZD_XX_STATE" || failures=1
    elif [ "${XX74_WROTE_STATE:-0}" = 1 ]; then
        rm -f "$MZD_XX_STATE" || failures=1
    fi
    [ "$failures" = 0 ]
}

xx74_abort() {
    local message="$1"
    if [ "$MZD_TRANSACTION_ACTIVE" = 1 ] && [ -n "$MZD_ROLLBACK_FN" ]; then
        if "$MZD_ROLLBACK_FN"; then
            mzd_popup "$message\n\nThe backed-up original state was restored.\nBoot autorun is not active."
        else
            mzd_popup "$message\n\nWARNING: the rollback could not be completely verified!\nKeep the USB stick and check mzd-usb.log."
        fi
        MZD_TRANSACTION_ACTIVE=0
        MZD_ROLLBACK_FN=""
    else
        mzd_popup "$message\n\nNothing was changed."
    fi
    mzd_finalize || true
    return 1
}

xx74_copy_backup_to_stick() {
    local target
    [ -n "$MZD_STICK" ] && [ -d "$MZD_STICK" ] || return 0
    [ -n "$MZD_BACKUP_DIR" ] || return 0
    target="$MZD_STICK/backup-xx74-$(basename "$MZD_BACKUP_DIR")"
    if [ -e "$target" ]; then
        mzd_log "USB backup copy already exists: $target"
        return 0
    fi
    if cp -a "$MZD_BACKUP_DIR" "$target" 2>/dev/null; then
        mzd_log "backup copied to USB: $target"
        return 0
    fi
    mzd_log "WARNING: boot autorun backup copy to USB failed"
    return 0
}

# Take a backup of original bytes. Sources are "name:path" pairs in $1.. .
xx74_take_backup() {
    local item name src
    mzd_backup_begin xx74-autorun || return 1
    for item in "$@"; do
        [ -n "$item" ] || continue
        name=${item%%:*}
        src=${item#*:}
        [ -n "$name" ] && [ -n "$src" ] || return 1
        mzd_backup_add "$src" "$name" || return 1
    done
    mzd_backup_publish || return 1
    xx74_copy_backup_to_stick
    return 0
}

xx74_write_state() {
    local name tmp sha
    sha=$(xx74_autorun_sha) || return 1
    tmp="$MZD_ROOT/tmp/xx74-state.$$"
    {
        printf 'format=mzd-xx74-v1\n'
        printf 'installer=%s\n' "$MZD_INSTALLER_VERSION"
        printf 'backup=%s\n' "$(basename "$MZD_BACKUP_DIR")"
        printf 'autorun=%s\n' "$sha"
        for name in $XX74_PRESENT; do
            printf 'file=%s\n' "$name"
        done
    } >"$tmp" || return 1
    sha=$(mzd_sha256_file "$tmp") || { rm -f "$tmp"; return 1; }
    if [ -f "$MZD_XX_STATE" ]; then
        cp "$MZD_XX_STATE" "$MZD_XX_DIR/.state.rollback" || { rm -f "$tmp"; return 1; }
        XX74_STATE_PREV=1
    fi
    if ! mzd_stage_copy "$tmp" "$MZD_XX_STATE" "$sha"; then
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
    mzd_publish_staged "$MZD_XX_STATE" "$sha" || return 1
    XX74_WROTE_STATE=1
    return 0
}

xx74_install_autorun() {
    local sha
    sha=$(xx74_autorun_sha) || return 1
    if [ -f "$MZD_XX_AUTORUN" ]; then
        cp "$MZD_XX_AUTORUN" "$MZD_XX_DIR/.autorun.rollback" || return 1
        XX74_AUTORUN_PREV=1
    fi
    mzd_stage_copy "$MZD_XX_STICK_AUTORUN" "$MZD_XX_AUTORUN" "$sha" || return 1
    chmod 755 "$MZD_XX_AUTORUN.mzd-new" || return 1
    mzd_publish_staged "$MZD_XX_AUTORUN" "$sha" || return 1
    XX74_WROTE_AUTORUN=1
    return 0
}

# Build the list of original sources for a new backup. Prints name:path lines.
xx74_backup_plan() {
    local name path class src
    xx74_collect_present || return 1
    [ -n "$XX74_PRESENT" ] || return 1
    : >"$MZD_ROOT/tmp/xx74-plan.$$"
    for name in $XX74_PRESENT; do
        path=$(xx74_path "$name") || return 1
        class=$(xx74_class "$path")
        case "$class" in
            stock)
                src=$path
                xx74_ends_with_newline "$src" || {
                    mzd_error "startup script has no final newline: $path"
                    return 1
                }
                ;;
            hooked)
                if [ -n "$MZD_BACKUP_DIR" ] && mzd_real_file "$MZD_BACKUP_DIR/$name"; then
                    src=$MZD_BACKUP_DIR/$name
                else
                    mzd_error "hooked script has no original in the backup: $name"
                    return 1
                fi
                ;;
            *)
                mzd_error "startup script is not safe to back up ($class): $name"
                return 1
                ;;
        esac
        printf '%s:%s\n' "$name" "$src" >>"$MZD_ROOT/tmp/xx74-plan.$$" || return 1
    done
    return 0
}

xx74_install_work() {
    local state plan_line name src n
    XX74_CHANGED=0
    XX74_APPLIED=""
    XX74_WROTE_AUTORUN=0
    XX74_AUTORUN_PREV=0
    XX74_WROTE_STATE=0
    XX74_STATE_PREV=0
    mzd_log "=== boot autorun: install ==="
    if ! mzd_require_firmware; then
        mzd_popup "Unsupported firmware.\n\nNothing was changed."
        return 1
    fi
    xx74_payload_ok || {
        mzd_popup "The boot autorun files on the stick are missing or damaged.\n\nNothing was changed."
        return 1
    }
    state=$(xx74_state)
    mzd_log "boot autorun state before install: $state"
    case "$state" in
        ours)
            return 0
            ;;
        foreign)
            mzd_popup "Boot autorun was already changed by something else.\n\nIt was left alone."
            return 1
            ;;
        missing)
            mzd_popup "The startup scripts this hook needs are missing.\n\nBoot autorun was not installed."
            return 1
            ;;
        clean|partial) ;;
        *)
            mzd_popup "Unknown boot autorun state ($state).\n\nNothing was changed."
            return 1
            ;;
    esac

    if [ "$state" = partial ]; then
        xx74_load_backup || MZD_BACKUP_DIR=""
    else
        MZD_BACKUP_DIR=""
    fi
    mkdir -p "$MZD_ROOT/tmp" || return 1
    if ! xx74_backup_plan; then
        rm -f "$MZD_ROOT/tmp/xx74-plan.$$"
        xx74_abort "Boot autorun cannot be repaired from the backup on this car."
        return 1
    fi
    # shellcheck disable=SC2046
    if ! xx74_take_backup $(tr '\n' ' ' <"$MZD_ROOT/tmp/xx74-plan.$$"); then
        rm -f "$MZD_ROOT/tmp/xx74-plan.$$"
        xx74_abort "The boot autorun backup could not be created and verified."
        return 1
    fi
    rm -f "$MZD_ROOT/tmp/xx74-plan.$$"

    if ! mzd_prepare_mutation; then
        xx74_abort "Mazda Connect could not be made writable."
        return 1
    fi
    MZD_TRANSACTION_ACTIVE=1
    MZD_ROLLBACK_FN=xx74_rollback_install
    mkdir -p "$MZD_XX_DIR" || { xx74_abort "The boot autorun directory could not be created."; return 1; }

    n=0
    for name in $XX74_PRESENT; do
        n=$((n + 1))
        if [ "$n" = 2 ]; then
            mzd_fault xx74-publish-fail && {
                xx74_abort "Boot autorun could not be written."
                return 1
            }
        fi
        if ! xx74_apply_name "$name"; then
            xx74_abort "The startup script could not be written: $name"
            return 1
        fi
    done
    if ! xx74_install_autorun; then
        xx74_abort "The autorun file could not be installed."
        return 1
    fi
    if ! xx74_write_state; then
        xx74_abort "The boot autorun marker could not be written."
        return 1
    fi

    state=$(xx74_state)
    if [ "$state" != ours ]; then
        xx74_abort "The final check of boot autorun failed ($state)."
        return 1
    fi
    MZD_TRANSACTION_ACTIVE=0
    MZD_ROLLBACK_FN=""
    rm -f "$MZD_XX_DIR/.autorun.rollback" "$MZD_XX_DIR/.state.rollback"
    mzd_log "boot autorun installation verified"
    if ! mzd_finalize; then
        mzd_popup "Boot autorun was written, but watchdog/rootfs could not be verified afterwards.\n\nDo not switch off the car now. Run the diagnosis."
        return 1
    fi
    mzd_popup "Boot autorun installed and verified.\n\nIt starts on the next restart of Mazda Connect."
    XX74_CHANGED=1
    return 0
}

xx74_install() {
    local rc
    xx74_enter
    xx74_install_work
    rc=$?
    xx74_leave
    return "$rc"
}

# ---------------------------------------------------------------------------
# Removal
# ---------------------------------------------------------------------------

xx74_restore_name() {
    local name="$1" dest rec sha
    dest=$(xx74_path "$name") || return 1
    mzd_backup_restore_stage "$name" "$dest" || return 1
    rec=$(mzd_backup_record "$name") || return 1
    sha=${rec%%|*}
    mzd_publish_staged "$dest" "$sha" || return 1
    if grep -q -F '# mzd-xx74 begin' "$dest" 2>/dev/null; then
        mzd_error "removal: hook still present in $name"
        return 1
    fi
    return 0
}

xx74_rollback_revert() {
    local name
    mzd_log "rollback of the boot autorun removal: restoring the originals again"
    for name in $XX74_PRESENT; do
        mzd_real_file "$MZD_BACKUP_DIR/$name" || return 1
        xx74_restore_name "$name" || return 1
    done
    return 0
}

xx74_revert_work() {
    local state name auto recorded current
    XX74_CHANGED=0
    mzd_log "=== boot autorun: remove ==="
    if ! mzd_require_firmware; then
        mzd_popup "Unsupported firmware.\n\nNothing was changed."
        return 1
    fi
    state=$(xx74_state)
    mzd_log "boot autorun state before removal: $state"
    case "$state" in
        clean|missing)
            return 0
            ;;
        foreign)
            mzd_log "boot autorun state foreign is left alone"
            return 0
            ;;
        ours|partial) ;;
        *)
            mzd_popup "Unknown boot autorun state ($state).\n\nNothing was changed."
            return 1
            ;;
    esac
    if ! xx74_load_backup; then
        mzd_popup "No valid backup of the boot autorun hook was found.\n\nRemoval is not possible.\nNothing was changed."
        return 1
    fi
    xx74_collect_present || return 1
    if ! mzd_prepare_mutation; then
        mzd_popup "Mazda Connect could not be made writable.\n\nNothing was changed."
        return 1
    fi
    MZD_TRANSACTION_ACTIVE=1
    MZD_ROLLBACK_FN=xx74_rollback_revert
    for name in $(xx74_state_files); do
        if ! mzd_real_file "$MZD_BACKUP_DIR/$name"; then
            xx74_abort "The backup is missing an original script ($name)."
            return 1
        fi
        if ! xx74_restore_name "$name"; then
            xx74_abort "The original startup script could not be restored ($name)."
            return 1
        fi
    done
    auto=$(xx74_autorun_class)
    recorded=$(xx74_state_value autorun 2>/dev/null || true)
    if [ "$auto" = absent ]; then
        :
    elif [ "$auto" = ours ]; then
        rm -f "$MZD_XX_AUTORUN" || { xx74_abort "The autorun file could not be removed."; return 1; }
    elif [ -f "$MZD_XX_AUTORUN" ]; then
        current=$(mzd_sha256_file "$MZD_XX_AUTORUN" 2>/dev/null || true)
        if [ -n "$recorded" ] && [ "$current" = "$recorded" ]; then
            rm -f "$MZD_XX_AUTORUN" || { xx74_abort "The autorun file could not be removed."; return 1; }
        else
            MZD_TRANSACTION_ACTIVE=0
            MZD_ROLLBACK_FN=""
            mzd_finalize || true
            mzd_popup "The startup scripts were restored.\nThe autorun file is not the one this installer wrote, so it was left in place."
            return 1
        fi
    fi
    rm -f "$MZD_XX_STATE" || { xx74_abort "The boot autorun marker could not be removed."; return 1; }
    MZD_TRANSACTION_ACTIVE=0
    MZD_ROLLBACK_FN=""
    state=$(xx74_state)
    if [ "$state" != clean ] && [ "$state" != missing ]; then
        xx74_abort "The removal of boot autorun could not be confirmed ($state)."
        return 1
    fi
    if ! mzd_finalize; then
        mzd_popup "Boot autorun was removed, but watchdog/rootfs could not be verified afterwards.\n\nDo not switch off the car now. Run the diagnosis."
        return 1
    fi
    mzd_log "boot autorun removed and the original scripts verified"
    mzd_popup "Boot autorun removed.\nThe original startup scripts were restored."
    XX74_CHANGED=1
    return 0
}

xx74_revert() {
    local rc
    xx74_enter
    xx74_revert_work
    rc=$?
    xx74_leave
    return "$rc"
}
