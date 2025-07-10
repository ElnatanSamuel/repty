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
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Function to draw a horizontal divider
draw_divider() {
  local width=80
  printf "${GRAY}%${width}s${NC}\n" | tr ' ' '─'
}

# Function to print a centered header
print_header() {
  local text="$1"
  local width=80
  local padding=$(( (width - ${#text}) / 2 ))
  printf "${GRAY}%${padding}s${BOLD}${CYAN}%s${NC}${GRAY}%${padding}s${NC}\n" "" "$text" ""
}

# Format the timestamp for better display
format_timestamp() {
  local timestamp="$1"
  # If timestamp is today, show only time
  if [[ "$timestamp" == "$(date +%Y-%m-%d)"* ]]; then
    echo "${timestamp:11:5}" # Extract only HH:MM
  # If timestamp is from this year, show month-day and time
  elif [[ "$timestamp" == "$(date +%Y)"* ]]; then
    echo "${timestamp:5:6} ${timestamp:11:5}" # Extract MM-DD HH:MM
  else
    echo "${timestamp:0:10}" # Extract only YYYY-MM-DD
  fi
}

# Function to add line numbers to results
add_line_numbers() {
  local num=1
  while IFS= read -r line; do
    printf " ${BOLD}${GREEN}%2d${NC} %s\n" "$num" "$line"
    num=$((num + 1))
  done
}

if [ -z "$QUERY" ]; then
  echo -e "\n${BOLD}${CYAN}Usage:${NC} repty nlp \"your natural language query\""
  echo -e "\n${BOLD}Examples:${NC}"
  echo -e "  ${CYAN}•${NC} repty nlp \"git commands I ran yesterday\""
  echo -e "  ${CYAN}•${NC} repty nlp \"failed commands in the last week\""
  echo -e "  ${CYAN}•${NC} repty nlp \"commands with docker and redis\""
  exit 1
fi

# Print a nice header
echo
draw_divider
print_header "REPTY SEARCH"
draw_divider
echo -e "\n${BOLD}Query:${NC} $QUERY\n"
draw_divider
echo

# Extract important terms from query
extract_query_terms() {
  local query="$1"
  local query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
  
  # Common command-line tools and operations to detect
  local important_terms="git docker npm node python pip aws curl wget ssh scp rsync tar zip unzip grep find sed awk head tail cat less more chmod chown mkdir rm cp mv ls ps kill systemctl service apt yum brew kubernetes k8s kubectl terraform ansible bash zsh fish vim emacs nano code make gcc clang javac go rust redis postgres mysql mongodb elasticsearch nginx apache tomcat wordpress jenkins jira jupyter jupyter-notebook"
  
  # Multi-word phrases to detect
  local phrases=(
    "docker compose"
    "git commit"
    "git push"
    "git pull"
    "git clone"
    "kubectl apply"
    "npm install"
  )
  
  # Initialize terms array
  local terms=()
  
  # Check for multi-word phrases
  for phrase in "${phrases[@]}"; do
    if [[ "$query_lower" == *"$phrase"* ]]; then
      terms+=("$phrase")
      # Also add individual words from the phrase
      for word in $phrase; do
        if [[ ! " ${terms[*]} " == *" $word "* ]]; then
          terms+=("$word")
        fi
      done
    fi
  done
  
  # Check for important single terms
  for term in $important_terms; do
    if [[ "$query_lower" == *"$term"* ]] && [[ ! " ${terms[*]} " == *" $term "* ]]; then
      terms+=("$term")
    fi
  done
  
  # Add other significant words from the query (non-stopwords)
  local stopwords="the a an in on at to for with by about of from this that these those etc then than and or but if when where how why who what which i you he she they them we us my your his her their our its am is are was were be been being have has had having do does did doing can could shall should will would may might must need"
  
  local words=$(echo "$query_lower" | tr -cs '[:alnum:]' ' ')
  for word in $words; do
    # Skip if word is already in terms, is a stopword, or is very short
    if [[ " ${terms[*]} " == *" $word "* || 
          " $stopwords " == *" $word "* || 
          ${#word} -le 2 ]]; then
      continue
    fi
    
    terms+=("$word")
  done
  
  # Join terms with spaces
  echo "${terms[*]}"
}

# Check if advanced NLP is available and enabled
if [ -f "$NLP_ENABLED_FLAG" ]; then
  # Check if we need to generate embeddings (only for new commands)
  NEW_COMMANDS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM commands WHERE id NOT IN (SELECT command_id FROM command_embeddings 2>/dev/null)" 2>/dev/null || echo 0)
  
  if [ "$NEW_COMMANDS" -gt 0 ]; then
    echo -e "${CYAN}▸${NC} Generating embeddings for $NEW_COMMANDS new commands..."
    # Try to generate embeddings, but don't fail if it doesn't work
    (python3 "$REPTY_EXT_DIR/generate_embeddings.py" >/dev/null 2>&1 || echo -e "${YELLOW}⚠${NC} Failed to generate embeddings, continuing with keyword search...") &
    PID=$!
    
    # Show a simple spinner while generating embeddings
    spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    i=0
    while kill -0 $PID 2>/dev/null; do
      i=$(( (i+1) % 10 ))
      printf "\r${CYAN}%s${NC} Processing..." "${spin:$i:1}"
      sleep .1
    done
    printf "\r${GREEN}✓${NC} Embeddings generated.           \n"
  fi
  
  # Try to use semantic search
  echo -e "${CYAN}▸${NC} Using semantic search..."
  
  # Extract key terms from query to display in output
  QUERY_TERMS=$(extract_query_terms "$QUERY")
  
  # If we found key terms, mention them
  if [ -n "$QUERY_TERMS" ]; then
    echo -e "${DIM}Detected key terms:${NC} ${MAGENTA}${QUERY_TERMS}${NC}"
  fi
  
  # Store results in a temporary file
  RESULTS_FILE=$(mktemp)
  python3 "$REPTY_EXT_DIR/semantic_search.py" "$QUERY" 2>/dev/null > "$RESULTS_FILE"
  
  if [ $? -eq 0 ] && [ -s "$RESULTS_FILE" ]; then
    # Format and display results
    echo -e "\n${BOLD}${GREEN}Search Results:${NC}"
    echo -e "${DIM}Tip: Enter a result number to copy the full command${NC}"
    draw_divider
    echo -e "${BOLD}     Time          Command                      Dir                  Score   Exit${NC}"
    draw_divider
    
    # Process and display results
    result_lines=()
    count=0
    while IFS='|' read -r id timestamp cwd command exit_code similarity; do
      if [ "$count" -lt "$MAX_RESULTS" ]; then
        # Format the timestamp for better display
        TS=$(format_timestamp "$timestamp")
        
        # Format the directory - show just the relevant part
        DIR=$(echo "$cwd" | rev | cut -d'/' -f1-2 | rev)
        if [ ${#DIR} -gt 18 ]; then
          DIR="...${DIR:(-15)}"
        fi
        
        # Format the command - truncate if too long but preserve beginning
        if [ ${#command} -gt 25 ]; then
          CMD="${command:0:25}..."
        else
          CMD="$command"
        fi
        
        # Format exit code with color
        if [ "$exit_code" -eq 0 ]; then
          EXIT_FORMAT="${GREEN}${exit_code}${NC}"
        else
          EXIT_FORMAT="${YELLOW}${exit_code}${NC}"
        fi
        
        # Display all results with valid similarity score
        if [[ "$similarity" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
          # Store the full command for later reference
          result_lines+=("$command")
          
          # Display result with formatting and line number
          printf " ${BOLD}${GREEN}%2d${NC} ${BOLD}${CYAN}%10s${NC}  %-28s %-20s ${GREEN}%5.2f${NC}   ${EXIT_FORMAT}\n" "$((count+1))" "$TS" "$CMD" "$DIR" "$similarity"
          count=$((count + 1))
        fi
      fi
    done < "$RESULTS_FILE"
    
    draw_divider
    
    # Interactive mode for copying commands
    if [ ${#result_lines[@]} -gt 0 ]; then
      echo -e "\n${CYAN}▸${NC} Enter a number to see the full command (or press Enter to exit): "
      read -r choice
      
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#result_lines[@]}" ]; then
        echo -e "\n${BOLD}${CYAN}Command:${NC}"
        echo -e "${result_lines[$((choice-1))]}"
        echo -e "\n${CYAN}▸${NC} Command has been copied to clipboard. Press Ctrl+Shift+V to paste it."
        
        # Try to copy to clipboard if available
        if command -v xclip >/dev/null 2>&1; then
          echo -n "${result_lines[$((choice-1))]}" | xclip -selection clipboard
        elif command -v pbcopy >/dev/null 2>&1; then
          echo -n "${result_lines[$((choice-1))]}" | pbcopy
        elif command -v clip.exe >/dev/null 2>&1; then
          echo -n "${result_lines[$((choice-1))]}" | clip.exe
        fi
      fi
    fi
    
    rm -f "$RESULTS_FILE"
    exit 0
  else
    echo -e "${YELLOW}⚠${NC} Semantic search returned no results or encountered an error."
    echo -e "${CYAN}▸${NC} Falling back to keyword matching...\n"
    rm -f "$RESULTS_FILE"
  fi
fi

# Extract keywords from query for searching
KEYWORDS=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' | sed 's/^ *//' | sed 's/ *$//')

# Use our more sophisticated keyword extractor
IMPORTANT_TERMS=$(extract_query_terms "$QUERY")

# Function to display results with consistent formatting
display_search_results() {
  local title="$1"
  local sql_query="$2"
  
  print_header "$title"
  echo -e "${DIM}Tip: Enter a result number to copy the full command${NC}"
  draw_divider
  echo -e "${BOLD}     Time          Command                      Dir                  Exit${NC}"
  draw_divider
  
  # Extract and process results
  RESULTS_FILE=$(mktemp)
  sqlite3 "$DB" "$sql_query" > "$RESULTS_FILE"
  
  # Process and display results with line numbers
  result_lines=()
  count=0
  while IFS='|' read -r timestamp command cwd exit_code; do
    TS=$(format_timestamp "$timestamp")
    
    # Format directory - show just the relevant part
    DIR=$(echo "$cwd" | rev | cut -d'/' -f1-2 | rev)
    if [ ${#DIR} -gt 18 ]; then
      DIR="...${DIR:(-15)}"
    fi
    
    # Format command - truncate if too long but preserve beginning
    if [ ${#command} -gt 25 ]; then
      CMD="${command:0:25}..."
    else
      CMD="$command"
    fi
    
    # Format exit code with color
    if [ "$exit_code" -eq 0 ]; then
      EXIT_FORMAT="${GREEN}${exit_code}${NC}"
    else
      EXIT_FORMAT="${YELLOW}${exit_code}${NC}"
    fi
    
    # Store the full command for later reference
    result_lines+=("$command")
    
    # Display result with formatting and line number
    printf " ${BOLD}${GREEN}%2d${NC} ${BOLD}${CYAN}%10s${NC}  %-28s %-20s   ${EXIT_FORMAT}\n" "$((count+1))" "$TS" "$CMD" "$DIR"
    count=$((count + 1))
  done < "$RESULTS_FILE"
  
  draw_divider
  
  # Interactive mode for copying commands
  if [ ${#result_lines[@]} -gt 0 ]; then
    echo -e "\n${CYAN}▸${NC} Enter a number to see the full command (or press Enter to exit): "
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#result_lines[@]}" ]; then
      echo -e "\n${BOLD}${CYAN}Command:${NC}"
      echo -e "${result_lines[$((choice-1))]}"
      echo -e "\n${CYAN}▸${NC} Command has been copied to clipboard. Press Ctrl+Shift+V to paste it."
      
      # Try to copy to clipboard if available
      if command -v xclip >/dev/null 2>&1; then
        echo -n "${result_lines[$((choice-1))]}" | xclip -selection clipboard
      elif command -v pbcopy >/dev/null 2>&1; then
        echo -n "${result_lines[$((choice-1))]}" | pbcopy
      elif command -v clip.exe >/dev/null 2>&1; then
        echo -n "${result_lines[$((choice-1))]}" | clip.exe
      fi
    fi
  fi
  
  rm -f "$RESULTS_FILE"
  exit 0
}

# Look for specific command-line tools/actions in the query
for TERM in $IMPORTANT_TERMS; do
  if [[ "$TERM" == "docker" || "$TERM" == "git" || "$TERM" == "npm" || "$TERM" == "node" || 
         "$TERM" == "python" || "$TERM" == "pip" || "$TERM" == "curl" || "$TERM" == "wget" || 
         "$TERM" == "apt" || "$TERM" == "yum" || "$TERM" == "redis" || "$TERM" == "postgres" ]]; then
    
    SQL_QUERY="
    SELECT 
      datetime(timestamp),
      command,
      cwd,
      exit_code
    FROM commands
    WHERE command LIKE '%$TERM%' OR keywords LIKE '%$TERM%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    
    display_search_results "COMMANDS WITH $TERM" "$SQL_QUERY"
  fi
done

# Look for time-related queries
if [[ "$QUERY" == *"yesterday"* ]]; then
  SQL_QUERY="
  SELECT 
    datetime(timestamp),
    command,
    cwd,
    exit_code
  FROM commands
  WHERE date(timestamp) = date('now', '-1 day')
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  
  display_search_results "COMMANDS FROM YESTERDAY" "$SQL_QUERY"
fi

if [[ "$QUERY" == *"today"* ]]; then
  SQL_QUERY="
  SELECT 
    datetime(timestamp),
    command,
    cwd,
    exit_code
  FROM commands
  WHERE date(timestamp) = date('now')
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  
  display_search_results "COMMANDS FROM TODAY" "$SQL_QUERY"
fi

if [[ "$QUERY" == *"last week"* ]]; then
  SQL_QUERY="
  SELECT 
    datetime(timestamp),
    command,
    cwd,
    exit_code
  FROM commands
  WHERE timestamp >= datetime('now', '-7 days')
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  
  display_search_results "COMMANDS FROM LAST WEEK" "$SQL_QUERY"
fi

# Look for status-related queries
if [[ "$QUERY" == *"failed"* || "$QUERY" == *"error"* || "$QUERY" == *"didn't work"* ]]; then
  SQL_QUERY="
  SELECT 
    datetime(timestamp),
    command,
    cwd,
    exit_code
  FROM commands
  WHERE exit_code != 0
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  
  display_search_results "FAILED COMMANDS" "$SQL_QUERY"
fi

# Look for common operations from the important terms
for op in $IMPORTANT_TERMS; do
  if [[ "$op" == "start" || "$op" == "stop" || "$op" == "run" || "$op" == "install" || 
         "$op" == "update" || "$op" == "remove" || "$op" == "create" || "$op" == "delete" || 
         "$op" == "build" || "$op" == "deploy" ]]; then
    
    SQL_QUERY="
    SELECT 
      datetime(timestamp),
      command,
      cwd,
      exit_code
    FROM commands
    WHERE command LIKE '%$op%' OR keywords LIKE '%$op%'
    GROUP BY command
    ORDER BY timestamp DESC
    LIMIT $MAX_RESULTS;
    "
    
    display_search_results "COMMANDS WITH '$op'" "$SQL_QUERY"
  fi
done

# If we have multiple important terms, search for commands containing ALL of them
if [[ $(echo "$IMPORTANT_TERMS" | wc -w) -gt 1 ]]; then
  # Build SQL query with conditions for each term
  SQL="
  SELECT 
    datetime(timestamp),
    command,
    cwd,
    exit_code
  FROM commands
  WHERE "
  
  for term in $IMPORTANT_TERMS; do
    SQL="${SQL}(command LIKE '%$term%' OR keywords LIKE '%$term%') AND "
  done
  
  SQL="${SQL% AND *} GROUP BY command ORDER BY timestamp DESC LIMIT $MAX_RESULTS;"
  
  display_search_results "COMMANDS MATCHING ALL TERMS: $IMPORTANT_TERMS" "$SQL"
fi

# Default search using all keywords
# Build the SQL query for keyword search
SQL="
SELECT 
  datetime(timestamp),
  command,
  cwd,
  exit_code
FROM commands
WHERE "

# Default to showing recent commands if no keywords extracted
if [ -z "$KEYWORDS" ]; then
  SQL="
  SELECT 
    datetime(timestamp),
    command,
    cwd,
    exit_code
  FROM commands
  GROUP BY command
  ORDER BY timestamp DESC
  LIMIT $MAX_RESULTS;
  "
  
  display_search_results "RECENT COMMANDS" "$SQL"
else
  # Add each keyword as a condition
  for word in $KEYWORDS; do
    SQL="${SQL}(command LIKE '%$word%' OR keywords LIKE '%$word%') AND "
  done
  
  # Remove the trailing "AND " and add sorting and limit
  SQL="${SQL% AND *} GROUP BY command ORDER BY timestamp DESC LIMIT $MAX_RESULTS;"
  
  display_search_results "SEARCH RESULTS FOR: $KEYWORDS" "$SQL"
fi 