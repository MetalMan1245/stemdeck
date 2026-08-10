#!/bin/bash
set -e

TMPDIR="$(mktemp -d /tmp/stemdeck.XXXXXX)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

REPO="stemdeckapp/stemdeck"
RELEASE_URL="https://github.com/${REPO}/releases/latest/download"

LOGO_URL="https://raw.githubusercontent.com/MetalMan1245/stemdeck/main/stemdeck-logo.png"

INSTALLER_URL="https://raw.githubusercontent.com/MetalMan1245/stemdeck/main/stemdeck-install.sh"

echo "[Remote Installer] Creating temp workspace..."
cd "$TMPDIR"

echo "[Remote Installer] Downloading CPU-only version..."
curl -fL \
    -o "StemDeck-Linux-x64.tar.gz" \
    "${RELEASE_URL}/StemDeck-Linux-x64.tar.gz"

echo "[Remote Installer] Downloading NVIDIA version..."
curl -fL \
    -o "StemDeck-Linux-x64.NVIDIA.tar.gz" \
    "${RELEASE_URL}/StemDeck-Linux-x64.NVIDIA.tar.gz"

echo "[Remote Installer] Downloading StemDeck logo..."
curl -fL \
    -o "stemdeck-logo.png" \
    "$LOGO_URL"

echo "[Remote Installer] Downloading local installer..."
curl -fL \
    -o "stemdeck-install.sh" \
    "$INSTALLER_URL"

echo "[Remote Installer] Running installer..."
chmod +x stemdeck-install.sh
./stemdeck-install.sh

echo "[Remote Installer] Done."
