#!/bin/bash

DB="$HOME/.repty.db"
OUT="$HOME/repty_history.md"

echo "# Repty Command History" > "$OUT"
echo "Generated on $(date)" >> "$OUT"
echo "" >> "$OUT"

TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM commands;")
echo "Total commands recorded: $TOTAL" >> "$OUT"
echo "" >> "$OUT"

echo "## Commands by Date" >> "$OUT"
echo "" >> "$OUT"

sqlite3 -cmd ".mode list" "$DB" "SELECT DISTINCT strftime('%Y-%m-%d', timestamp) FROM commands ORDER BY timestamp DESC;" | while read -r date; do
  echo "### $date" >> "$OUT"
  echo "" >> "$OUT"
  
  sqlite3 -cmd ".mode list" "$DB" "SELECT timestamp, command, cwd, exit_code FROM commands WHERE strftime('%Y-%m-%d', timestamp) = '$date' ORDER BY timestamp DESC;" | while IFS='|' read -r timestamp command cwd exit_code; do
    time=$(echo "$timestamp" | cut -d' ' -f2)
    status="Yes"
    if [ "$exit_code" != "0" ]; then
      status="No"
    fi
    
    echo "- $status **$time** \`$command\` (in \`$cwd\`)" >> "$OUT"
  done
  
  echo "" >> "$OUT"
done

echo "Exported to $OUT"
