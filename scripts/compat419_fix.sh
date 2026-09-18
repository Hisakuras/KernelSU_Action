#!/usr/bin/env bash
# Fix SukiSU-Ultra compilation errors on kernel 4.19
# Applied after KernelSU install, before build
set -euo pipefail

KSU_DIR="${KERNEL_DIR}/drivers/kernelsu"

if [ ! -f "$KSU_DIR/ksu.c" ]; then
    echo "[-] KSU dir not found at $KSU_DIR; skipping compat fixes"
    exit 0
fi

echo "[*] Applying kernel 4.19 compatibility fixes to SukiSU..."

# Fix 1: Add fallthrough macro for kernel < 5.4
if ! grep -q "define fallthrough" "$KSU_DIR/kernel_includes.h" 2>/dev/null; then
    sed -i '/#endif \/\/ __KSU_H_KERNEL_INCLUDES/i\
\
/* Compat: fallthrough macro was added in 5.4 */\
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 4, 0)\
#ifndef fallthrough\
#define fallthrough do {} while (0)\
#endif\
#endif' "$KSU_DIR/kernel_includes.h"
    echo "  [+] Added fallthrough compat macro"
fi

# Fix 2: Add no-op stubs for selinux_hide functions on kernel < 5.10
# selinux_hide.c uses 5.10+ internal SELinux structs and CANNOT compile on 4.19.
if ! grep -q "compat_selinux_hide_stubs" "$KSU_DIR/ksu.c" 2>/dev/null; then
    # Find the line number of "#include "runtime/ksud.c""
    KSUD_LINE=$(grep -n '#include "runtime/ksud.c"' "$KSU_DIR/ksu.c" | head -1 | cut -d: -f1)
    if [ -n "$KSUD_LINE" ]; then
        # Split file: everything before KSUD_LINE, stubs, everything from KSUD_LINE onward
        TMPFILE=$(mktemp)
        head -n $((KSUD_LINE - 1)) "$KSU_DIR/ksu.c" > "$TMPFILE"
        cat >> "$TMPFILE" << 'STUBEOF'

/* compat_selinux_hide_stubs: no-op stubs for kernel < 5.10 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 10, 0)
static inline void ksu_selinux_hide_handle_post_fs_data(void) {}
static inline void ksu_selinux_hide_handle_second_stage(void) {}
static inline void ksu_selinux_hide_drop_backup_if_unused(void) {}
#endif

STUBEOF
        tail -n +${KSUD_LINE} "$KSU_DIR/ksu.c" >> "$TMPFILE"
        mv "$TMPFILE" "$KSU_DIR/ksu.c"
        echo "  [+] Added selinux_hide stubs for kernel < 5.10 (before line $KSUD_LINE)"
    else
        echo "  [-] Could not find #include runtime/ksud.c in ksu.c"
    fi
fi

# Fix 3: Fix USER_ARG_NULL dereference in sulog/event.c
if grep -q '#define USER_ARG_NULL user_arg_null_ptr()' "$KSU_DIR/sulog/event.c"; then
    sed -i 's/#define USER_ARG_NULL user_arg_null_ptr()/#define USER_ARG_NULL (*user_arg_null_ptr())/' "$KSU_DIR/sulog/event.c"
    echo "  [+] Fixed USER_ARG_NULL pointer dereference"
fi

echo "[+] Kernel 4.19 compat fixes applied"
