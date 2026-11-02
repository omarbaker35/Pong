#!/bin/zsh
# Resolve real script location even when opened via a Desktop symlink
SCRIPT_PATH="${0:A}"
PROJECT_DIR="${SCRIPT_PATH:h}"
cd "$PROJECT_DIR" || exit 1
exec /Applications/love.app/Contents/MacOS/love "$PROJECT_DIR"
