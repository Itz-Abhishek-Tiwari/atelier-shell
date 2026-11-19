#!/usr/bin/env bash
# Build the qt6ct Qt platform theme + style into ~/.local (no root, no cmake, no Qt tools needed).
# It lets Qt/KDE apps (Dolphin, ...) follow the active atelier theme: `atelier-theme apply` writes
# ~/.config/qt6ct/{qt6ct.conf,colors/atelier.conf} and ~/.config/kdeglobals, and the plugin
# re-reads them live (about 3 s after a change).
#
# Re-run after a Qt upgrade (the plugin is built against the exact Qt version and uses Qt private
# headers; Qt refuses to load a plugin from another version and apps then fall back to default colours).
# Needs: git, gcc, make, qmake6 and the Qt6 headers (qt6-base). Source: github.com/trialuser02/qt6ct (BSD-2).
set -euo pipefail

PREFIX="$HOME/.local"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --depth 1 -q https://github.com/trialuser02/qt6ct.git "$WORK/qt6ct"
cd "$WORK/qt6ct"

# Qt 6.12 renamed this private header (…themes_p.h -> …theme_p.h). Patch whichever name is installed.
hdr_dir=$(find /usr/include/qt6/QtGui -type d -path '*/QtGui/private' | head -1)
if [ -f "$hdr_dir/qgenericunixtheme_p.h" ] && [ ! -f "$hdr_dir/qgenericunixthemes_p.h" ]; then
  sed -i 's#private/qgenericunixthemes_p.h#private/qgenericunixtheme_p.h#' src/qt6ct-qtplugin/qt6ctplatformtheme.h
fi

# The top-level project insists on Qt's translation tool (lrelease); we only need these three parts.
cat > mini.pro <<'PRO'
CONFIG += ordered
TEMPLATE = subdirs
SUBDIRS += src/qt6ct-common src/qt6ct-qtplugin src/qt6ct-style
PRO

mkdir build && cd build
qmake6 PREFIX="$PREFIX" "QMAKE_LFLAGS+=-Wl,-rpath,$PREFIX/lib" ../mini.pro >/dev/null
make -j"$(nproc)" >/dev/null

mkdir -p "$PREFIX/lib/qt6/plugins/platformthemes" "$PREFIX/lib/qt6/plugins/styles" "$PREFIX/share/qt6ct"
cp -a src/qt6ct-common/libqt6ct-common.so* "$PREFIX/lib/"
cp -a src/qt6ct-qtplugin/libqt6ct.so "$PREFIX/lib/qt6/plugins/platformthemes/"
cp -a src/qt6ct-style/libqt6ct-style.so "$PREFIX/lib/qt6/plugins/styles/"
cp -a ../qss "$PREFIX/share/qt6ct/"

echo "qt6ct installed in $PREFIX. Use: QT_QPA_PLATFORMTHEME=qt6ct QT_PLUGIN_PATH=$PREFIX/lib/qt6/plugins"
echo "Then apply a theme: atelier-theme apply \$(atelier-theme current)"
