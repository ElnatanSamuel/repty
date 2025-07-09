#!/bin/bash

DB="$HOME/.repty.db"
QUERY="$*"

if [ -z "$QUERY" ]; then
  echo "Usage: repty nlp \"your natural language query\""
  echo "Examples:"
  echo "  repty nlp \"git commands I ran yesterday\""
  echo "  repty nlp \"failed commands in the last week\""
  echo "  repty nlp \"commands I ran in the project directory\""
  exit 1
fi

echo "Analyzing query: '$QUERY'"
echo "----------------------------------------"

REPTY_EXT_DIR="$(dirname "$(realpath "$0")")/ext"
mkdir -p "$REPTY_EXT_DIR"

# Handle git commands
if [[ "$QUERY" == *"git"* ]]; then
  echo "Finding git commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE command LIKE 'git%'
  ORDER BY timestamp DESC
  LIMIT 20;"
  exit 0
fi

# Handle yesterday queries
if [[ "$QUERY" == *"yesterday"* ]]; then
  echo "Finding commands from yesterday..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE date(timestamp) = date('now', '-1 day')
  ORDER BY timestamp DESC;"
  exit 0
fi

# Handle last week queries
if [[ "$QUERY" == *"last week"* ]]; then
  echo "Finding commands from the last week..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE timestamp >= datetime('now', '-7 days')
  ORDER BY timestamp DESC;"
  exit 0
fi

# Handle today queries
if [[ "$QUERY" == *"today"* ]]; then
  echo "Finding commands from today..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE date(timestamp) = date('now')
  ORDER BY timestamp DESC;"
  exit 0
fi

# Handle failed/error commands
if [[ "$QUERY" == *"failed"* || "$QUERY" == *"error"* || "$QUERY" == *"didn't work"* ]]; then
  echo "Finding failed commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE exit_code != 0
  ORDER BY timestamp DESC
  LIMIT 20;"
  exit 0
fi

# Handle npm/node commands
if [[ "$QUERY" == *"npm"* || "$QUERY" == *"node"* ]]; then
  echo "Finding npm/node commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE command LIKE 'npm%' OR command LIKE 'node%'
  ORDER BY timestamp DESC
  LIMIT 20;"
  exit 0
fi

# Handle docker commands
if [[ "$QUERY" == *"docker"* ]]; then
  echo "Finding docker commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE command LIKE 'docker%'
  ORDER BY timestamp DESC
  LIMIT 20;"
  exit 0
fi

# Handle most used/frequent/common commands
if [[ "$QUERY" == *"most used"* || "$QUERY" == *"frequent"* || "$QUERY" == *"common"* ]]; then
  echo "Finding most frequently used commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    command AS \"Command\",
    COUNT(*) AS \"Count\"
  FROM commands
  GROUP BY command
  ORDER BY Count DESC
  LIMIT 10;"
  exit 0
fi

# Handle recent/latest/last commands
if [[ "$QUERY" == *"recent"* || "$QUERY" == *"latest"* || "$QUERY" == *"last"* ]]; then
  echo "Finding most recent commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  ORDER BY timestamp DESC
  LIMIT 10;"
  exit 0
fi

# Handle directory/folder/path queries
if [[ "$QUERY" == *"directory"* || "$QUERY" == *"folder"* || "$QUERY" == *"path"* ]]; then
  DIR_PATTERN=$(echo "$QUERY" | grep -oP '(?<=directory |folder |path |in )[^ ]+' || echo "")
  
  if [ -n "$DIR_PATTERN" ]; then
    echo "Finding commands in directory containing '$DIR_PATTERN'..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE cwd LIKE '%$DIR_PATTERN%'
    ORDER BY timestamp DESC
    LIMIT 20;"
  else
    echo "Finding commands grouped by directory..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT
      cwd AS \"Directory\",
      COUNT(*) AS \"Command Count\"
    FROM commands
    GROUP BY cwd
    ORDER BY \"Command Count\" DESC
    LIMIT 10;"
  fi
  exit 0
fi

# Handle project queries
if [[ "$QUERY" == *"project"* ]]; then
  PROJ_PATTERN=$(echo "$QUERY" | grep -oP '(?<=project )[^ ]+' || echo "")
  
  if [ -n "$PROJ_PATTERN" ]; then
    echo "Finding commands in project containing '$PROJ_PATTERN'..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE git_project LIKE '%$PROJ_PATTERN%'
    ORDER BY timestamp DESC
    LIMIT 20;"
  else
    echo "Finding commands grouped by project..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT
      git_project AS \"Project\",
      COUNT(*) AS \"Command Count\"
    FROM commands
    WHERE git_project != ''
    GROUP BY git_project
    ORDER BY \"Command Count\" DESC
    LIMIT 10;"
  fi
  exit 0
fi

# Handle advanced installation
if [[ "$QUERY" == "--install-advanced" ]]; then
  echo "This feature is not yet implemented in the simplified version."
  echo "The basic pattern matching is still available."
  exit 0
fi

# Default case - use fuzzy search with the query terms
KEYWORDS=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | sed -E 's/\b(the|a|an|in|on|at|to|for|with|by|about|like|show|find|get|give|me|my|i|command[s]?|ran|run|executed|used|typed|entered|from|that|which|what|where|when|how|who|why|did|do|does|is|are|was|were|be|been|being|have|has|had|having|can|could|shall|should|will|would|may|might|must|need|ought|use[d]?|using|let[']?s)\b//g' | tr -s '[:space:]' | sed 's/^ //g' | sed 's/ $//g')

if [ -z "$KEYWORDS" ]; then
  echo "Could not extract meaningful keywords from your query."
  echo "Try being more specific or use one of the example queries."
  exit 1
fi

echo "Searching for: $KEYWORDS"

SQL_QUERY="SELECT datetime(timestamp) AS \"Timestamp\", cwd AS \"Directory\", command AS \"Command\", exit_code AS \"Exit Code\" FROM commands WHERE "

for KEYWORD in $KEYWORDS; do
  SQL_QUERY="$SQL_QUERY command LIKE '%$KEYWORD%' OR "
done

SQL_QUERY="${SQL_QUERY% OR *} ORDER BY timestamp DESC LIMIT 20;"

sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "$SQL_QUERY"

# Show notice about advanced capabilities
if [ ! -f "$REPTY_EXT_DIR/.nlp_notice_shown" ]; then
  echo ""
  echo "----------------------------------------"
  echo "💡 Want more advanced NLP capabilities?"
  echo ""
  echo "You can install a lightweight embedding model for better natural language understanding:"
  echo ""
  echo "  repty nlp --install-advanced"
  echo ""
  echo "This will download a small (~25MB) model for improved query understanding."
  echo "All processing remains local and offline."
  echo "----------------------------------------"
  
  touch "$REPTY_EXT_DIR/.nlp_notice_shown"
fi 