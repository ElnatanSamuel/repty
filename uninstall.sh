#!/bin/bash

echo "Removing Repty..."

rm -rf "$HOME/.repty"
rm -f "$HOME/repty_history.md"
rm -f "$HOME/.repty.db"

if [ -f "$HOME/.zshrc" ]; then
  echo "Cleaning up .zshrc..."
  sed -i '/repty_log()/,/^}/d' "$HOME/.zshrc"
  sed -i '/precmd() { repty_log }/d' "$HOME/.zshrc"
  sed -i '/export PATH="$HOME\/.repty\/bin:$PATH"/d' "$HOME/.zshrc"
fi

if [ -f "$HOME/.bashrc" ]; then
  echo "Cleaning up .bashrc..."
  sed -i '/repty_log()/,/^}/d' "$HOME/.bashrc"
  sed -i '/PROMPT_COMMAND="repty_log"/d' "$HOME/.bashrc"
  sed -i '/export PATH="$HOME\/.repty\/bin:$PATH"/d' "$HOME/.bashrc"
fi

echo "Repty has been removed. Restart your terminal to finish cleanup."
