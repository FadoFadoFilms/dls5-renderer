#!/bin/sh
set -eu
cd "$(dirname "$0")"
python3 ./generate_installer.py
for dll in kernel32 user32 shell32 advapi32 gdi32; do
  lld-link /dll /noentry /machine:x64 /def:${dll}.def /out:${dll}.dummy.dll /implib:${dll}.lib
  rm -f "${dll}.dummy.dll"
done
clang --target=x86_64-pc-windows-msvc -c installer.c -o installer.obj -std=c11 -Os -ffreestanding -fno-stack-protector -fno-builtin -mstack-probe-size=65536
lld-link /entry:WinMainCRTStartup /subsystem:windows /machine:x64 /nodefaultlib /stack:1048576,65536 installer.obj kernel32.lib user32.lib shell32.lib advapi32.lib gdi32.lib /out:RTX2060-DLSS5-Offline-Test-Setup-AutoLatest.exe
