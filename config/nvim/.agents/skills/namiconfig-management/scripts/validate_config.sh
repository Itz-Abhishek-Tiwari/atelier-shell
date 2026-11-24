#!/usr/bin/env bash
# ==============================================================================
# NamiConfig Headless Validation Script
# ==============================================================================
# Validates Lua syntax and Neovim initialization headlessly to ensure no errors.

set -e

echo "🔍 Validating NamiConfig Lua syntax..."

# Check all .lua files with luac or nvim if available
ERRORS=0
for f in $(find lua -name "*.lua") init.lua; do
  if ! luac -p "$f" 2>/dev/null; then
    # Fallback check using nvim headless compilation check if luac isn't installed
    nvim --headless -c "luafile $f" -c "q" >/dev/null 2>&1 || {
      echo "❌ Syntax error in $f"
      ERRORS=$((ERRORS + 1))
    }
  fi
done

if [ $ERRORS -gt 0 ]; then
  echo "❌ Found $ERRORS Lua syntax errors."
  exit 1
fi

echo "🚀 Bootstrapping Neovim in headless mode..."
OUTPUT=$(nvim --headless -c "q" 2>&1)

if echo "$OUTPUT" | grep -iE "error|failed|traceback" | grep -v "Downloading" | grep -v "Cloning"; then
  echo "⚠️ Warning: Neovim output contains warnings/errors during headless startup:"
  echo "$OUTPUT"
  exit 1
else
  echo "✅ NamiConfig validated successfully with zero startup errors!"
fi
