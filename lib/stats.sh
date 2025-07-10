#!/bin/bash

DB="$HOME/.repty.db"

echo "Repty Stats"
echo "-----------------------"

sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<'EOF'
SELECT COUNT(*) AS "Total Commands" FROM commands;

SELECT command AS "Command", COUNT(*) as "Count"
FROM commands
GROUP BY command
ORDER BY Count DESC
LIMIT 10;

SELECT strftime('%Y-%m-%d', timestamp) AS "Date", COUNT(*) AS "Commands"
FROM commands
GROUP BY Date
ORDER BY Date DESC
LIMIT 5;
EOF
