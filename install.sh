#!/bin/bash

REPO_URL="https://github.com/ElnatanSamuel/repty.git"
INSTALL_DIR="$HOME/.repty"
BIN_DIR="$INSTALL_DIR/bin"
LIB_DIR="$INSTALL_DIR/lib"
EXT_DIR="$LIB_DIR/ext"

echo "Getting Repty..."

rm -rf "$INSTALL_DIR"

echo "Cloning repo $REPO_URL into $INSTALL_DIR"
pwd

git clone --branch dev-el "$REPO_URL" "$INSTALL_DIR" || {
  echo "Failed to clone repo"; exit 1;
}

if [[ ! -f "$BIN_DIR/repty" ]]; then
  echo "Error: $BIN_DIR/repty not found after cloning."
  exit 1
fi

# Create directories
mkdir -p "$EXT_DIR"

# Make scripts executable
chmod +x "$BIN_DIR/repty"
chmod +x "$LIB_DIR/"*.sh
chmod +x "$EXT_DIR/"*.py 2>/dev/null || true

# Initialize the database
echo "Initializing database..."
bash "$LIB_DIR/bootstrap.sh"

if [[ $SHELL == */zsh ]]; then
  echo 'Adding Repty to .zshrc...'
  {
    echo ''
    echo 'repty_log() {'
    echo '  local EXIT_CODE=$?'
    echo '  local CMD=$(fc -ln -1 | sed "s/^\s*//")'
    echo '  "$HOME/.repty/bin/repty" log "$EXIT_CODE" "$CMD"'
    echo '}'
    echo 'precmd_functions+=(repty_log)'
  } >> "$HOME/.zshrc"
  SHELL_RC="$HOME/.zshrc"
elif [[ $SHELL == */bash ]]; then
  echo 'Adding Repty to .bashrc...'
  {
    echo ''
    echo 'repty_log() {'
    echo '  local EXIT_CODE=$?'
    echo '  local CMD=$(HISTTIMEFORMAT="" history 1 | sed "s/^[ 0-9]\+[ ]\+//")'
    echo '  "$HOME/.repty/bin/repty" log "$EXIT_CODE" "$CMD"'
    echo '}'
    echo 'PROMPT_COMMAND="repty_log"'
  } >> "$HOME/.bashrc"
  SHELL_RC="$HOME/.bashrc"
else
  echo "Unknown shell. Manual setup might be needed."
  SHELL_RC=""
fi

# Add repty bin directory to PATH if not already added
if [[ -n "$SHELL_RC" ]]; then
  if ! grep -q 'export PATH="$HOME/.repty/bin:$PATH"' "$SHELL_RC"; then
    echo 'export PATH="$HOME/.repty/bin:$PATH"' >> "$SHELL_RC"
    echo "Added repty bin directory to PATH in $SHELL_RC"
  else
    echo "PATH to repty bin already present in $SHELL_RC"
  fi
fi

echo "Repty has been installed. Restart your terminal or run 'source ~/.zshrc' or 'source ~/.bashrc'"
