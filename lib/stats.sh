#!/bin/bash

DB="$HOME/.repty.db"

echo "Repty Stats"
echo "-----------------------"

sqlite3 "$DB" <<'EOF'
SELECT 'Total Commands:' AS label, COUNT(*) FROM commands;

SELECT 'Most Used Commands:' AS label, command, COUNT(*) as count
FROM commands
GROUP BY command
ORDER BY count DESC
LIMIT 5;
EOF
