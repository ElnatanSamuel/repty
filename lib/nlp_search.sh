#!/bin/bash

DB="$HOME/.repty.db"
QUERY="$*"
REPTY_LIB_DIR="$(dirname "$(realpath "$0")")"
REPTY_EXT_DIR="$REPTY_LIB_DIR/ext"
NLP_ENABLED_FLAG="$REPTY_EXT_DIR/.nlp_enabled"
MAX_RESULTS=7  # Limit the number of results displayed

# ANSI color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

if [ -z "$QUERY" ]; then
  echo -e "${BOLD}Usage:${NC} repty nlp \"your natural language query\""
  echo -e "\n${BOLD}Examples:${NC}"
  echo "  repty nlp \"git commands I ran yesterday\""
  echo "  repty nlp \"failed commands in the last week\""
  echo "  repty nlp \"commands I ran in the project directory\""
  exit 1
fi

echo -e "\n${BOLD}${CYAN}Analyzing query:${NC} '$QUERY'"
echo -e "${CYAN}----------------------------------------${NC}\n"

# Check if advanced NLP is available and enabled
if [ -f "$NLP_ENABLED_FLAG" ]; then
  # Check if we need to generate embeddings (only for new commands)
  NEW_COMMANDS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM commands WHERE id NOT IN (SELECT command_id FROM command_embeddings)")
  
  if [ "$NEW_COMMANDS" -gt 0 ]; then
    echo "Generating embeddings for $NEW_COMMANDS new commands..."
    # Try to generate embeddings, but don't fail if it doesn't work
    (python3 "$REPTY_EXT_DIR/generate_embeddings.py" >/dev/null 2>&1 || echo "Warning: Failed to generate embeddings, continuing with keyword search...") &
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
  echo -e "${BOLD}Using semantic search...${NC}"
  
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
    echo -e "Detected key terms:$key_terms"
  fi
  
  # Perform semantic search
  RESULTS=$(python3 "$REPTY_EXT_DIR/semantic_search.py" "$QUERY" 2>/dev/null)
  
  if [ $? -eq 0 ] && [ -n "$RESULTS" ]; then
    # Format and display results
    echo -e "\n${BOLD}${GREEN}Search Results:${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${BOLD}Timestamp            Command                     Score${NC}"
    echo -e "${CYAN}-------------------- --------------------------- -------${NC}"
    
    count=0
    echo "$RESULTS" | while IFS='|' read -r id timestamp cwd command exit_code similarity; do
      if [ "$count" -lt "$MAX_RESULTS" ]; then
        # Format the output - truncate command if too long
        CMD=$(echo "$command" | cut -c 1-25)
        if [ ${#command} -gt 25 ]; then
          CMD="${CMD}..."
        fi
        
        # Display all results with valid similarity score
        if [[ "$similarity" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          printf "${YELLOW}%-20s${NC} %-27s ${GREEN}%.2f${NC}\n" "$timestamp" "$CMD" "$similarity"
          # Show directory on a second indented line
          printf "               ${BLUE}%s${NC}\n" "${cwd:0:50}"
          count=$((count + 1))
        fi
      fi
    done
    exit 0
  else
    echo "Semantic search returned no results or encountered an error."
    echo -e "${YELLOW}Falling back to keyword matching...${NC}\n"
  fi
fi

# Handle specific git commands
if [[ "$QUERY" == *"git"* ]]; then
  if [[ "$QUERY" == *"stage"* || "$QUERY" == *"add"* ]]; then
    echo -e "${BOLD}${GREEN}Finding git add/stage commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 10 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git add%' OR command LIKE 'git stage%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  elif [[ "$QUERY" == *"commit"* ]]; then
    echo -e "${BOLD}${GREEN}Finding git commit commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git commit%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  elif [[ "$QUERY" == *"push"* ]]; then
    echo -e "${BOLD}${GREEN}Finding git push commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git push%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  elif [[ "$QUERY" == *"pull"* ]]; then
    echo -e "${BOLD}${GREEN}Finding git pull commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git pull%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  elif [[ "$QUERY" == *"clone"* ]]; then
    echo -e "${BOLD}${GREEN}Finding git clone commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git clone%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  elif [[ "$QUERY" == *"branch"* ]]; then
    echo -e "${BOLD}${GREEN}Finding git branch commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git branch%' OR command LIKE 'git checkout%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  elif [[ "$QUERY" == *"stash"* ]]; then
    echo -e "${BOLD}${GREEN}Finding git stash commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git stash%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  elif [[ "$QUERY" == *"head"* ]]; then
    echo -e "${BOLD}${GREEN}Finding git head commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git head%' OR command LIKE 'git show HEAD%' OR command LIKE 'git log HEAD%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  else
    echo -e "${BOLD}${GREEN}Finding git commands...${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
    SELECT DISTINCT
      datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
      substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
      substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
      exit_code AS \"${BOLD}Code${NC}\"
    FROM commands
    WHERE command LIKE 'git%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    exit 0
  fi
fi

# Handle curl commands
if [[ "$QUERY" == *"curl"* ]]; then
  echo -e "${BOLD}${GREEN}Finding curl commands...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
    substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
    substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
    exit_code AS \"${BOLD}Code${NC}\"
  FROM commands
  WHERE command LIKE '%curl%'
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Handle yesterday queries
if [[ "$QUERY" == *"yesterday"* ]]; then
  echo -e "${BOLD}${GREEN}Finding commands from yesterday...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
    substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
    substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
    exit_code AS \"${BOLD}Code${NC}\"
  FROM commands
  WHERE date(timestamp) = date('now', '-1 day')
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Handle last week queries
if [[ "$QUERY" == *"last week"* ]]; then
  echo -e "${BOLD}${GREEN}Finding commands from the last week...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
    substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
    substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
    exit_code AS \"${BOLD}Code${NC}\"
  FROM commands
  WHERE timestamp >= datetime('now', '-7 days')
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Handle today queries
if [[ "$QUERY" == *"today"* ]]; then
  echo -e "${BOLD}${GREEN}Finding commands from today...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
    substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
    substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
    exit_code AS \"${BOLD}Code${NC}\"
  FROM commands
  WHERE date(timestamp) = date('now')
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Handle failed/error commands
if [[ "$QUERY" == *"failed"* || "$QUERY" == *"error"* || "$QUERY" == *"didn't work"* ]]; then
  echo -e "${BOLD}${GREEN}Finding failed commands...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
    substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
    substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
    exit_code AS \"${BOLD}Code${NC}\"
  FROM commands
  WHERE exit_code != 0
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Handle npm/node commands
if [[ "$QUERY" == *"npm"* || "$QUERY" == *"node"* ]]; then
  echo -e "${BOLD}${GREEN}Finding npm/node commands...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
    substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
    substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
    exit_code AS \"${BOLD}Code${NC}\"
  FROM commands
  WHERE command LIKE 'npm%' OR command LIKE 'node%'
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Handle docker commands
if [[ "$QUERY" == *"docker"* ]]; then
  echo -e "${BOLD}${GREEN}Finding docker commands...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
    substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
    substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
    exit_code AS \"${BOLD}Code${NC}\"
  FROM commands
  WHERE command LIKE '%docker%'
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Handle most used/frequent/common commands
if [[ "$QUERY" == *"most used"* || "$QUERY" == *"frequent"* || "$QUERY" == *"common"* ]]; then
  echo -e "${BOLD}${GREEN}Finding most frequently used commands...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 40 10" "$DB" "
  SELECT
    substr(command, 1, 40) AS \"${BOLD}Command${NC}\",
    COUNT(*) AS \"${BOLD}Count${NC}\"
  FROM commands
  GROUP BY command
  ORDER BY Count DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Handle recent/latest/last commands
if [[ "$QUERY" == *"recent"* || "$QUERY" == *"latest"* || "$QUERY" == *"last"* || "$QUERY" == *"history"* ]]; then
  echo -e "${BOLD}${GREEN}Finding recent commands...${NC}"
  echo -e "${CYAN}----------------------------------------${NC}"
  sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "
  SELECT DISTINCT
    datetime(timestamp) AS \"${BOLD}Timestamp${NC}\",
    substr(command, 1, 30) AS \"${BOLD}Command${NC}\",
    substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\",
    exit_code AS \"${BOLD}Code${NC}\"
  FROM commands
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  exit 0
fi

# Default case - use fuzzy search with the query terms
KEYWORDS=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | sed -E 's/\b(the|a|an|in|on|at|to|for|with|by|about|like|show|find|get|give|me|my|i|command[s]?|ran|run|executed|used|typed|entered|from|that|which|what|where|when|how|who|why|did|do|does|is|are|was|were|be|been|being|have|has|had|having|can|could|shall|should|will|would|may|might|must|need|ought|use[d]?|using|let[']?s)\b//g' | tr -s '[:space:]' | sed 's/^ //g' | sed 's/ $//g')

if [ -z "$KEYWORDS" ]; then
  echo "Could not extract meaningful keywords from your query."
  echo "Try being more specific or use one of the example queries."
  exit 1
fi

echo -e "${BOLD}${GREEN}Searching for: $KEYWORDS${NC}"
echo -e "${CYAN}----------------------------------------${NC}"

SQL_QUERY="
SELECT DISTINCT 
  datetime(timestamp) AS \"${BOLD}Timestamp${NC}\", 
  substr(command, 1, 30) AS \"${BOLD}Command${NC}\", 
  substr(cwd, 1, 20) AS \"${BOLD}Directory${NC}\", 
  exit_code AS \"${BOLD}Code${NC}\" 
FROM commands 
WHERE "

for KEYWORD in $KEYWORDS; do
  SQL_QUERY="$SQL_QUERY command LIKE '%$KEYWORD%' OR keywords LIKE '%$KEYWORD%' OR "
done

SQL_QUERY="${SQL_QUERY% OR *} GROUP BY command ORDER BY timestamp DESC LIMIT $MAX_RESULTS;"

sqlite3 -cmd ".mode column" -cmd ".headers on" -cmd ".width 20 30 20 10" "$DB" "$SQL_QUERY" 