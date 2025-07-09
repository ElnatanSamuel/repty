#!/bin/bash

DB="$HOME/.repty.db"
QUERY="$*"

if [ -z "$QUERY" ]; then
  echo "Usage: repty find \"search text\""
  exit 1
fi

sqlite3 -cmd ".mode column" "$DB" <<EOF
SELECT
  timestamp,
  cwd,
  printf("%.50s...", command) AS cmd_preview,
  exit_code
FROM commands
WHERE command LIKE '%' || '$QUERY' || '%'
ORDER BY timestamp DESC
LIMIT 20;
EOF
