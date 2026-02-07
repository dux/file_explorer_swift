#!/bin/bash
set -e

APP_NAME="FileExplorer"
REPO="dux/file_explorer_swift"
INSTALL_DIR="$HOME/Applications"
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/FileExplorer.app.tar.gz"

# colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; exit 1; }

# --- check macOS ---
if [[ "$(uname)" != "Darwin" ]]; then
  error "This app requires macOS"
fi

# --- check arch ---
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  error "Unsupported architecture: $ARCH"
fi

info "Installing $APP_NAME..."

# --- install homebrew if missing ---
if ! command -v brew &>/dev/null; then
  warn "Homebrew not found, installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # add brew to PATH for current session
  if [[ "$ARCH" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

ok "Homebrew ready"

# --- brew dependencies ---
DEPS=(libimobiledevice fd ffmpeg)

info "Checking dependencies..."
to_install=()
for pkg in "${DEPS[@]}"; do
  if brew list "$pkg" &>/dev/null; then
    ok "$pkg"
  else
    to_install+=("$pkg")
  fi
done

if [[ ${#to_install[@]} -gt 0 ]]; then
  info "Installing: ${to_install[*]}"
  brew install "${to_install[@]}"
  ok "Installed: ${to_install[*]}"
fi

# --- download and install app ---
info "Downloading $APP_NAME..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fSL "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME.app.tar.gz"
ok "Downloaded"

info "Extracting..."
tar -xzf "$TMP_DIR/$APP_NAME.app.tar.gz" -C "$TMP_DIR"

if [[ ! -d "$TMP_DIR/$APP_NAME.app" ]]; then
  error "Archive does not contain $APP_NAME.app"
fi

# --- kill running instance ---
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.3 || true

# --- install to ~/Applications ---
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"
ok "Installed to $INSTALL_DIR/$APP_NAME.app"

# --- launch ---
info "Launching $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
ok "$APP_NAME installed successfully!"
