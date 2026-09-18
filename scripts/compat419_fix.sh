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
# In kernel_includes.h, add before the final #endif
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

# Fix 2: Add stub implementations for selinux_hide functions on kernel < 5.10
# The real selinux_hide.c uses 5.10+ internal SELinux structs (status_lock, status_page, policy)
# so it CANNOT compile on 4.19. Instead, we provide no-op stubs after the #endif.
if ! grep -q "compat_selinux_hide_stubs" "$KSU_DIR/ksu.c" 2>/dev/null; then
    python3 -c "
import re
with open('$KSU_DIR/ksu.c', 'r') as f:
    content = f.read()

# Find the '#endif' after selinux_hide.c include and add stubs before it
stubs = '''
/* compat: no-op stubs for kernel < 5.10 where selinux_hide.c is excluded */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 10, 0)
/* compat_selinux_hide_stubs */
static inline void ksu_selinux_hide_handle_post_fs_data(void) {}
static inline void ksu_selinux_hide_handle_second_stage(void) {}
static inline void ksu_selinux_hide_drop_backup_if_unused(void) {}
#endif
'''
# Insert stubs between '#endif' (the one closing selinux_hide.c guard) and '#include "runtime/ksud.c"'
pattern = r'(#endif\s*\n)(#include \"runtime/ksud\.c\")'
replacement = r'\1' + stubs.strip() + '\n\n\2'
content = re.sub(pattern, replacement, content, count=1)

with open('$KSU_DIR/ksu.c', 'w') as f:
    f.write(content)
"
    echo "  [+] Added selinux_hide stubs for kernel < 5.10"
fi

# Fix 3: Fix USER_ARG_NULL dereference in sulog/event.c
# user_arg_null_ptr() returns a pointer, but the parameter expects a value
if grep -q '#define USER_ARG_NULL user_arg_null_ptr()' "$KSU_DIR/sulog/event.c"; then
    sed -i 's/#define USER_ARG_NULL user_arg_null_ptr()/#define USER_ARG_NULL (*user_arg_null_ptr())/' "$KSU_DIR/sulog/event.c"
    echo "  [+] Fixed USER_ARG_NULL pointer dereference"
fi

echo "[+] Kernel 4.19 compat fixes applied"
