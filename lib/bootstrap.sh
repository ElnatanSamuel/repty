#!/bin/bash

DB="$HOME/.repty.db"

if ! command -v sqlite3 &>/dev/null; then
  echo "SQLite3 not found. Attempting to install..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt update && sudo apt install -y sqlite3
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install sqlite
  else
    echo "Unsupported OS. Please install sqlite3 manually."
    exit 1
  fi
fi

sqlite3 "$DB" <<'EOF'
CREATE TABLE IF NOT EXISTS commands (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  command TEXT,
  timestamp TEXT,
  cwd TEXT,
  exit_code INTEGER,
  git_project TEXT,
  session_id TEXT
);
EOF
