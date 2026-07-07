#!/bin/sh
set -e

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
linux*) OS='linux' ;;
darwin*) OS='macos' ;;
*) echo "Unsupported OS: $OS" && exit 1 ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
x86_64) ARCH='x86_64' ;;
arm64 | aarch64) ARCH='aarch64' ;;
i386 | i686) ARCH='x86' ;;
*) echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac

if [ "$OS" = "macos" ] && [ "$ARCH" = "x86" ]; then
  echo "macOS 32-bit is unsupported" && exit 1
fi

RELEASE_JSON=$(curl -sSfL "https://api.github.com/repos/Satheeshsk369/zigup/releases/latest")
TAG=$(echo "$RELEASE_JSON" | grep '"tag_name":' | sed -E 's/.*"tag_name":\s*"(.*)".*/\1/')
if [ -z "$TAG" ]; then
  echo "Failed to fetch latest tag from GitHub releases" && exit 1
fi

BINARY_NAME="zigup-${ARCH}-${OS}"
DOWNLOAD_URL="https://github.com/Satheeshsk369/zigup/releases/download/${TAG}/${BINARY_NAME}"

BIN_DIR="${XDG_DATA_HOME:-$HOME/.local}/bin"
mkdir -p "$BIN_DIR"

echo "Downloading zigup for ${OS}-${ARCH}..."
curl -sSfL "$DOWNLOAD_URL" -o "$BIN_DIR/zigup"
chmod +x "$BIN_DIR/zigup"

echo "Successfully installed zigup to $BIN_DIR/zigup"
