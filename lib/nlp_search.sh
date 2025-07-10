#!/bin/bash

DB="$HOME/.repty.db"
QUERY="$*"
REPTY_LIB_DIR="$(dirname "$(realpath "$0")")"
REPTY_EXT_DIR="$REPTY_LIB_DIR/ext"
NLP_ENABLED_FLAG="$REPTY_EXT_DIR/.nlp_enabled"

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

# Check if advanced NLP is available and enabled
if [ -f "$NLP_ENABLED_FLAG" ]; then
  # Check if we need to generate embeddings (only for new commands)
  NEW_COMMANDS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM commands WHERE id NOT IN (SELECT command_id FROM command_embeddings)")
  
  if [ "$NEW_COMMANDS" -gt 0 ]; then
    echo "Generating embeddings for $NEW_COMMANDS new commands..."
    python3 "$REPTY_EXT_DIR/generate_embeddings.py" >/dev/null 2>&1 &
    PID=$!
    
    # Show a simple spinner while generating embeddings
    spin='-\|/'
    i=0
    while kill -0 $PID 2>/dev/null; do
      i=$(( (i+1) % 4 ))
      printf "\r[%c] Processing... " "${spin:$i:1}"
      sleep .1
    done
    printf "\rEmbeddings generated.           \n"
  fi
  
  # Try to use semantic search
  echo "Using semantic search..."
  
  # Extract key terms from query to display in output
  query_terms=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alpha:]' ' ')
  key_terms=""
  
  # Check each word against a list of common command-line terms
  for term in $query_terms; do
    # Common command line tools and operations
    if [[ " git docker npm node python pip aws curl wget ssh scp rsync tar zip unzip grep find sed awk head tail cat less more chmod chown mkdir rm cp mv ls ps kill systemctl service apt yum brew " =~ " $term " ]]; then
      key_terms="$key_terms $term"
    fi
  done
  
  # If we found key terms, mention them
  if [ -n "$key_terms" ]; then
    echo "Detected key terms:$key_terms"
  fi
  
  # Perform semantic search
  RESULTS=$(python3 "$REPTY_EXT_DIR/semantic_search.py" "$QUERY" 2>/dev/null)
  
  if [ $? -eq 0 ] && [ -n "$RESULTS" ]; then
    # Format and display results
    echo "Timestamp            | Command                                             | Directory (Score)"
    echo "-------------------- | -------------------------------------------------- | -----------------"
    echo "$RESULTS" | while IFS='|' read -r id timestamp cwd command exit_code similarity; do
      # Format the output - truncate command if too long
      CMD=$(echo "$command" | cut -c 1-50)
      # Display all results with valid similarity score
      if [[ "$similarity" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf "%-20s | %-50s | %s (%.2f)\n" "$timestamp" "$CMD" "$cwd" "$similarity"
      fi
    done
    exit 0
  else
    echo "Semantic search returned no results."
    echo "Falling back to pattern matching..."
  fi
fi

# Handle specific git commands
if [[ "$QUERY" == *"git"* ]]; then
  # Check for specific git operations
  if [[ "$QUERY" == *"stage"* || "$QUERY" == *"add"* ]]; then
    echo "Finding git add/stage commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git add%' OR command LIKE 'git stage%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  elif [[ "$QUERY" == *"commit"* ]]; then
    echo "Finding git commit commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git commit%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  elif [[ "$QUERY" == *"push"* ]]; then
    echo "Finding git push commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git push%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  elif [[ "$QUERY" == *"pull"* ]]; then
    echo "Finding git pull commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git pull%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  elif [[ "$QUERY" == *"clone"* ]]; then
    echo "Finding git clone commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git clone%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  elif [[ "$QUERY" == *"branch"* ]]; then
    echo "Finding git branch commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git branch%' OR command LIKE 'git checkout%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  elif [[ "$QUERY" == *"stash"* ]]; then
    echo "Finding git stash commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git stash%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  elif [[ "$QUERY" == *"head"* ]]; then
    echo "Finding git head commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git head%' OR command LIKE 'git show HEAD%' OR command LIKE 'git log HEAD%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  else
    echo "Finding git commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE command LIKE 'git%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT 20;"
    exit 0
  fi
fi

# Handle yesterday queries
if [[ "$QUERY" == *"yesterday"* ]]; then
  echo "Finding commands from yesterday..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE date(timestamp) = date('now', '-1 day')
  GROUP BY command
  ORDER BY timestamp DESC;"
  exit 0
fi

# Handle last week queries
if [[ "$QUERY" == *"last week"* ]]; then
  echo "Finding commands from the last week..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE timestamp >= datetime('now', '-7 days')
  GROUP BY command
  ORDER BY timestamp DESC;"
  exit 0
fi

# Handle today queries
if [[ "$QUERY" == *"today"* ]]; then
  echo "Finding commands from today..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE date(timestamp) = date('now')
  GROUP BY command
  ORDER BY timestamp DESC;"
  exit 0
fi

# Handle failed/error commands
if [[ "$QUERY" == *"failed"* || "$QUERY" == *"error"* || "$QUERY" == *"didn't work"* ]]; then
  echo "Finding failed commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE exit_code != 0
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT 20;"
  exit 0
fi

# Handle npm/node commands
if [[ "$QUERY" == *"npm"* || "$QUERY" == *"node"* ]]; then
  echo "Finding npm/node commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE command LIKE 'npm%' OR command LIKE 'node%'
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT 20;"
  exit 0
fi

# Handle docker commands
if [[ "$QUERY" == *"docker"* ]]; then
  echo "Finding docker commands..."
  sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  WHERE command LIKE 'docker%'
  GROUP BY command
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
  SELECT DISTINCT
    datetime(timestamp) AS \"Timestamp\",
    cwd AS \"Directory\",
    command AS \"Command\",
    exit_code AS \"Exit Code\"
  FROM commands
  GROUP BY command
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
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE cwd LIKE '%$DIR_PATTERN%'
    GROUP BY command
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
    SELECT DISTINCT
      datetime(timestamp) AS \"Timestamp\",
      cwd AS \"Directory\",
      command AS \"Command\",
      exit_code AS \"Exit Code\"
    FROM commands
    WHERE git_project LIKE '%$PROJ_PATTERN%'
    GROUP BY command
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

# Default case - use fuzzy search with the query terms
KEYWORDS=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | sed -E 's/\b(the|a|an|in|on|at|to|for|with|by|about|like|show|find|get|give|me|my|i|command[s]?|ran|run|executed|used|typed|entered|from|that|which|what|where|when|how|who|why|did|do|does|is|are|was|were|be|been|being|have|has|had|having|can|could|shall|should|will|would|may|might|must|need|ought|use[d]?|using|let[']?s)\b//g' | tr -s '[:space:]' | sed 's/^ //g' | sed 's/ $//g')

if [ -z "$KEYWORDS" ]; then
  echo "Could not extract meaningful keywords from your query."
  echo "Try being more specific or use one of the example queries."
  exit 1
fi

echo "Searching for: $KEYWORDS"

SQL_QUERY="SELECT DISTINCT datetime(timestamp) AS \"Timestamp\", cwd AS \"Directory\", command AS \"Command\", exit_code AS \"Exit Code\" FROM commands WHERE "

for KEYWORD in $KEYWORDS; do
  SQL_QUERY="$SQL_QUERY command LIKE '%$KEYWORD%' OR "
done

SQL_QUERY="${SQL_QUERY% OR *} GROUP BY command ORDER BY timestamp DESC LIMIT 20;"

sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" "$SQL_QUERY" 