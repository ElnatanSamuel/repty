#!/bin/bash

REPO_URL="https://github.com/ElnatanSamuel/repty.git"
INSTALL_DIR="$HOME/.repty"
BIN_DIR="$INSTALL_DIR/bin"

echo "Getting Repty..."

rm -rf "$INSTALL_DIR"

git clone "$REPO_URL" "$INSTALL_DIR" || {
  echo "Failed to clone repo"; exit 1;
}

chmod +x "$BIN_DIR/repty"
chmod +x "$BIN_DIR/export-md.sh"
chmod +x "$BIN_DIR/stats.sh"

if [[ $SHELL == */zsh ]]; then
  echo 'Adding Repty to .zshrc...'
  {
    echo ''
    echo 'repty_log() { "$HOME/.repty/bin/repty" log "$?" ; }'
    echo 'precmd() { repty_log }'
  } >> "$HOME/.zshrc"
elif [[ $SHELL == */bash ]]; then
  echo 'Adding Repty to .bashrc...'
  {
    echo ''
    echo 'repty_log() { "$HOME/.repty/bin/repty" log "$?" ; }'
    echo 'PROMPT_COMMAND="repty_log"'
  } >> "$HOME/.bashrc"
else
  echo "Unknown shell. Manual setup might be needed."
fi

echo "Repty has been installed. Restart your terminal or run 'source ~/.zshrc' or 'source ~/.bashrc'"
