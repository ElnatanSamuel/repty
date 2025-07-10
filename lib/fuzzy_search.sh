#!/bin/bash

DB="$HOME/.repty.db"
QUERY="$*"
MAX_RESULTS=10  # Limit the number of results displayed

# ANSI color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

if [ -z "$QUERY" ]; then
  echo -e "${BOLD}Usage:${NC} repty find \"search term\""
  exit 1
fi

echo -e "${BOLD}${GREEN}Searching for commands containing: '${QUERY}'${NC}"
echo -e "${CYAN}----------------------------------------${NC}"

# Use SQLite to search for commands containing the query term
sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 40 10" "$DB" "
SELECT DISTINCT
  datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
  substr(cwd, 1, 40) AS \"${BOLD}Directory${NC}\",
  substr(command, 1, 40) AS \"${BOLD}Command${NC}\",
  exit_code AS \"${BOLD}Code${NC}\"
FROM commands
WHERE command LIKE '%$QUERY%' OR keywords LIKE '%$QUERY%'
GROUP BY command
ORDER BY timestamp DESC
LIMIT $MAX_RESULTS;
"
