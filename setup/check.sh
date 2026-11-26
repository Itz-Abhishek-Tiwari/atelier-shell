#!/usr/bin/env bash
# check.sh: quick health check for this repo and the running desktop. Read-only.
#
#   setup/check.sh            run everything
#   setup/check.sh --repo     only the static checks on the files (no running desktop needed)
#
# Exit code 0 = nothing wrong, 1 = at least one problem. Warnings do not fail the run.
# For a deeper look at the live desktop, use the "doctor" skill.
cd "$(dirname "$0")/.." || exit 1

bad=0 warn=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; bad=$((bad + 1)); }
note() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; warn=$((warn + 1)); }

echo "Shell scripts"
mapfile -t sh < <(git ls-files '*.sh')
for f in "${sh[@]}"; do bash -n "$f" 2>/dev/null || fail "syntax: $f"; done
if command -v shellcheck >/dev/null; then
    out=$(shellcheck -S error -f gcc "${sh[@]}" 2>&1) && ok "shellcheck: no errors in ${#sh[@]} scripts" || fail "shellcheck errors:"$'\n'"$out"
else
    note "shellcheck is not installed (sudo pacman -S shellcheck)"
fi

echo "Python"
mapfile -t py < <(git ls-files '*.py'; echo theming/atelier-theme)
pyfail=0
for f in "${py[@]}"; do
    python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])" "$f" 2>/dev/null || { fail "syntax: $f"; pyfail=1; }
done
[ $pyfail -eq 0 ] && ok "syntax: ${#py[@]} files"

echo "Lua (Hyprland config)"
luafail=0
for f in $(git ls-files 'hypr/*.lua'); do luac -p "$f" 2>/dev/null || { fail "syntax: $f"; luafail=1; }; done
[ $luafail -eq 0 ] && ok "syntax: hypr/*.lua"

echo "Repo"
[ -z "$(git status --porcelain)" ] && ok "work tree clean" || note "uncommitted changes: $(git status --porcelain | wc -l) paths"
git fetch -q origin 2>/dev/null
ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo "?")
[ "$ahead" = "0" ] && ok "everything is pushed" || note "$ahead commit(s) not pushed"
broken=$(find greeter quickshell hypr config -xtype l 2>/dev/null)
[ -z "$broken" ] && ok "no broken symlinks" || fail "broken symlinks:"$'\n'"$broken"

[ "${1:-}" = "--repo" ] && { echo; echo "$bad problem(s), $warn warning(s)"; [ $bad -eq 0 ]; exit; }

echo "Running desktop"
if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
    errs=$(hyprctl configerrors 2>&1 | grep -v '^$')
    [ -z "$errs" ] && ok "hyprctl configerrors is empty" || fail "Hyprland config errors:"$'\n'"$errs"
else
    note "Hyprland is not running; skipped"
fi
if command -v qs >/dev/null && qs list >/dev/null 2>&1; then
    n=$(qs log --no-color 2>/dev/null | grep -E 'ERROR|ReferenceError|TypeError|is not defined' | grep -vc textinput)
    [ "$n" -eq 0 ] && ok "Quickshell log has no errors" || fail "Quickshell log has $n error line(s): qs log | grep -E 'ERROR|ReferenceError|TypeError'"
else
    note "Quickshell is not running; skipped"
fi
failed=$(systemctl --failed --no-legend 2>/dev/null; systemctl --user --failed --no-legend 2>/dev/null)
[ -z "$failed" ] && ok "no failed systemd units" || fail "failed units:"$'\n'"$failed"
cores=$(coredumpctl list --since '-7d' --no-legend --no-pager 2>/dev/null | grep -c . || true)
[ "${cores:-0}" -eq 0 ] && ok "no crash dumps in the last 7 days" || note "$cores crash dump(s) in the last 7 days: coredumpctl list --since -7d"
orph=$(pacman -Qdtq 2>/dev/null | grep -c debug || true)
[ "${orph:-0}" -eq 0 ] && ok "no orphaned -debug packages" || note "$orph orphaned -debug package(s): pacman -Qdtq"

echo
echo "$bad problem(s), $warn warning(s)"
[ $bad -eq 0 ]
