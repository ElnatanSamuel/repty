#!/bin/bash

DB="$HOME/.repty.db"
OUT="$HOME/repty_history.md"

echo "# Repty Command History" > "$OUT"
echo "" >> "$OUT"

sqlite3 -cmd ".mode list" "$DB" "SELECT timestamp, command FROM commands ORDER BY timestamp DESC;" | while IFS='|' read -r timestamp command; do
  echo "- **$timestamp**: \`$command\`" >> "$OUT"
done

echo "Exported to $OUT"
