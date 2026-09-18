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

# Fix 2: Remove version guard around selinux_hide.c inclusion in ksu.c
# The file handles its own version checks internally
if grep -q 'feature/selinux_hide.c' "$KSU_DIR/ksu.c"; then
    python3 -c "
import re
with open('$KSU_DIR/ksu.c', 'r') as f:
    lines = f.readlines()

new_lines = []
for i, line in enumerate(lines):
    if 'include \"feature/selinux_hide.c\"' in line:
        if new_lines and 'KERNEL_VERSION(5, 10, 0)' in new_lines[-1]:
            new_lines.pop()
        new_lines.append(line)
        for j in range(i+1, min(i+3, len(lines))):
            if lines[j].strip() == '#endif':
                lines[j] = ''
                break
        continue
    new_lines.append(line)

with open('$KSU_DIR/ksu.c', 'w') as f:
    f.writelines(new_lines)
"
    echo "  [+] Removed selinux_hide.c version guard"
fi

# Fix 3: Fix USER_ARG_NULL dereference in sulog/event.c
# user_arg_null_ptr() returns a pointer, but the parameter expects a value
if grep -q '#define USER_ARG_NULL user_arg_null_ptr()' "$KSU_DIR/sulog/event.c"; then
    sed -i 's/#define USER_ARG_NULL user_arg_null_ptr()/#define USER_ARG_NULL (*user_arg_null_ptr())/' "$KSU_DIR/sulog/event.c"
    echo "  [+] Fixed USER_ARG_NULL pointer dereference"
fi

echo "[+] Kernel 4.19 compat fixes applied"
