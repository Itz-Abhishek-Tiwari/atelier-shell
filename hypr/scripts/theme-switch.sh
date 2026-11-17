#!/usr/bin/env bash
# ==============================================================================
#  Quickshell Atelier - Theme Cycler (Native Quickshell UI)
# ==============================================================================

if [ -n "$1" ]; then
    quickshell ipc call theme set "$1"
else
    quickshell ipc call theme cycle
fi
