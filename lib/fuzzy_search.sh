#!/bin/bash

DB="$HOME/.repty.db"
QUERY="$*"

if [ -z "$QUERY" ]; then
  echo "Usage: repty find \"search text\""
  exit 1
fi

echo "Searching for commands containing: '$QUERY'"
echo "----------------------------------------"

sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE command LIKE '%' || '$QUERY' || '%'
ORDER BY timestamp DESC
LIMIT 20;
EOF

if [ $? -ne 0 ]; then
  echo "No results found or database error."
fi
