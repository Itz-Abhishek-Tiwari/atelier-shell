#!/usr/bin/env bash
# Compiles the fragment shaders (*.frag) into the .qsb files the shell loads.
# Qt's shader tool is /usr/lib/qt6/bin/qsb (package qt6-shadertools); it is not on PATH.
#
#   ./build.sh            rebuild every shader
#   ./build.sh spread     rebuild one
#
# Output names (what modules/background/Background.qml loads):
#   spreadmap.frag  ->  spreadmap.frag.qsb
#   spread.frag     ->  spread.v3.frag.qsb     (the "v3" is bumped by hand when the shader
#                                               changes; Quickshell caches by file name, so a
#                                               new name makes it load the new build)
# After bumping the version, update the path in Background.qml and delete the old .qsb.
set -euo pipefail
cd "$(dirname "$0")"

QSB="$(command -v qsb || echo /usr/lib/qt6/bin/qsb)"
[ -x "$QSB" ] || { echo "qsb not found; install qt6-shadertools" >&2; exit 1; }

out_name() {
    case "$1" in
        spread) echo "spread.v3.frag.qsb" ;;
        *)      echo "$1.frag.qsb" ;;
    esac
}

if [ $# -gt 0 ]; then files=("$1.frag"); else files=(*.frag); fi

for src in "${files[@]}"; do
    [ -f "$src" ] || { echo "no such shader: $src" >&2; exit 1; }
    name="${src%.frag}"
    out="$(out_name "$name")"
    "$QSB" --qt6 -o "$out" "$src"
    echo "built $out"
done
