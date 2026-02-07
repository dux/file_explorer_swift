#!/bin/bash

APP_NAME="FileExplorerByDux"
REPO="dux/file_explorer_swift"
INSTALL_DIR="/Applications"
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$APP_NAME.app.tar.gz"

info() { echo "* $1"; }
fail() { echo "ERROR: $1"; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "macOS required"

info "Installing $APP_NAME..."

# install homebrew if missing
if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fail "Homebrew install failed"
  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# install dependencies one by one
for pkg in libimobiledevice fd ffmpeg duti; do
  brew list "$pkg" &>/dev/null || brew install "$pkg"
done

# download app
TMP_DIR="$(mktemp -d)"
info "Downloading..."
curl -fSL "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME.app.tar.gz" || fail "Download failed"
tar -xzf "$TMP_DIR/$APP_NAME.app.tar.gz" -C "$TMP_DIR"
[[ -d "$TMP_DIR/$APP_NAME.app" ]] || fail "Bad archive"

# install
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.3 || true
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"
rm -rf "$TMP_DIR"

info "Installed to $INSTALL_DIR/$APP_NAME.app"

# set as default folder handler
if command -v duti &>/dev/null; then
  info "Setting as default folder handler..."
  duti -s com.dux.file-explorer public.folder all
fi

open "$INSTALL_DIR/$APP_NAME.app"
