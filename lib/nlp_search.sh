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

case "$QUERY" in
  *"yesterday"*)
    echo "Finding commands from yesterday..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE date(timestamp) = date('now', '-1 day')
ORDER BY timestamp DESC;
EOF
    ;;
    
  *"last week"*)
    echo "Finding commands from the last week..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE timestamp >= datetime('now', '-7 days')
ORDER BY timestamp DESC;
EOF
    ;;
    
  *"today"*)
    echo "Finding commands from today..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE date(timestamp) = date('now')
ORDER BY timestamp DESC;
EOF
    ;;
    
  *"failed"* | *"error"* | *"didn't work"*)
    echo "Finding failed commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE exit_code != 0
ORDER BY timestamp DESC
LIMIT 20;
EOF
    ;;
    
  *"git"*)
    echo "Finding git commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE command LIKE 'git%'
ORDER BY timestamp DESC
LIMIT 20;
EOF
    ;;
    
  *"npm"* | *"node"*)
    echo "Finding npm/node commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE command LIKE 'npm%' OR command LIKE 'node%'
ORDER BY timestamp DESC
LIMIT 20;
EOF
    ;;
    
  *"docker"*)
    echo "Finding docker commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE command LIKE 'docker%'
ORDER BY timestamp DESC
LIMIT 20;
EOF
    ;;
    
  *"most used"* | *"frequent"* | *"common"*)
    echo "Finding most frequently used commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  command AS "Command",
  COUNT(*) AS "Count"
FROM commands
GROUP BY command
ORDER BY Count DESC
LIMIT 10;
EOF
    ;;
    
  *"recent"* | *"latest"* | *"last"*)
    echo "Finding most recent commands..."
    sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
ORDER BY timestamp DESC
LIMIT 10;
EOF
    ;;
    
  *"directory"* | *"folder"* | *"path"*)
    DIR_PATTERN=$(echo "$QUERY" | grep -oP '(?<=directory |folder |path |in )[^ ]+'  || echo "")
    
    if [ -n "$DIR_PATTERN" ]; then
      echo "Finding commands in directory containing '$DIR_PATTERN'..."
      sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE cwd LIKE '%$DIR_PATTERN%'
ORDER BY timestamp DESC
LIMIT 20;
EOF
    else
      echo "Finding commands grouped by directory..."
      sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  cwd AS "Directory",
  COUNT(*) AS "Command Count"
FROM commands
GROUP BY cwd
ORDER BY "Command Count" DESC
LIMIT 10;
EOF
    fi
    ;;
    
  *"project"*)
    PROJ_PATTERN=$(echo "$QUERY" | grep -oP '(?<=project )[^ ]+' || echo "")
    
    if [ -n "$PROJ_PATTERN" ]; then
      echo "Finding commands in project containing '$PROJ_PATTERN'..."
      sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  datetime(timestamp) AS "Timestamp",
  cwd AS "Directory",
  command AS "Command",
  exit_code AS "Exit Code"
FROM commands
WHERE git_project LIKE '%$PROJ_PATTERN%'
ORDER BY timestamp DESC
LIMIT 20;
EOF
    else
      echo "Finding commands grouped by project..."
      sqlite3 -cmd ".mode column" -cmd ".headers on" "$DB" <<EOF
SELECT
  git_project AS "Project",
  COUNT(*) AS "Command Count"
FROM commands
WHERE git_project != ''
GROUP BY git_project
ORDER BY "Command Count" DESC
LIMIT 10;
EOF
    fi
    ;;
    
  *)
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
    ;;
esac

if [ $? -ne 0 ]; then
  echo "No results found or database error."
fi

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

if [ "$QUERY" = "--install-advanced" ]; then
  echo "Installing advanced NLP capabilities..."
  
  if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
  fi
  
  VENV_DIR="$REPTY_EXT_DIR/venv"
  if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
  fi
  
  echo "Installing required Python packages..."
  source "$VENV_DIR/bin/activate"
  pip install --quiet sentence-transformers sqlite-utils
  
  EMBED_SCRIPT="$REPTY_EXT_DIR/generate_embeddings.py"
  cat > "$EMBED_SCRIPT" <<'PYTHON'
import sys
import sqlite3
from sentence_transformers import SentenceTransformer
import numpy as np

# Load a lightweight model
model = SentenceTransformer('all-MiniLM-L6-v2')

# Connect to database
db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Check if embeddings table exists, create if not
cursor.execute('''
CREATE TABLE IF NOT EXISTS command_embeddings (
    command_id INTEGER PRIMARY KEY,
    embedding BLOB,
    FOREIGN KEY (command_id) REFERENCES commands(id)
)
''')

# Get commands without embeddings
cursor.execute('''
SELECT id, command FROM commands 
WHERE id NOT IN (SELECT command_id FROM command_embeddings)
''')

commands = cursor.fetchall()

if commands:
    print(f"Generating embeddings for {len(commands)} commands...")
    
    # Generate embeddings in batches
    batch_size = 100
    for i in range(0, len(commands), batch_size):
        batch = commands[i:i+batch_size]
        ids = [cmd[0] for cmd in batch]
        texts = [cmd[1] for cmd in batch]
        
        # Generate embeddings
        embeddings = model.encode(texts)
        
        # Store embeddings
        for j, embedding in enumerate(embeddings):
            cmd_id = ids[j]
            # Convert numpy array to bytes
            embedding_bytes = np.array(embedding).tobytes()
            cursor.execute('INSERT INTO command_embeddings (command_id, embedding) VALUES (?, ?)',
                          (cmd_id, embedding_bytes))
        
        conn.commit()
        print(f"Processed {min(i+batch_size, len(commands))}/{len(commands)} commands")

# Create a function to search by similarity
conn.create_function('cosine_similarity', 2, lambda x, y: 
                     np.dot(np.frombuffer(x, dtype=np.float32), 
                            np.frombuffer(y, dtype=np.float32)) / 
                     (np.linalg.norm(np.frombuffer(x, dtype=np.float32)) * 
                      np.linalg.norm(np.frombuffer(y, dtype=np.float32))))

print("Embeddings generated and stored in database")
conn.close()
PYTHON

  SEARCH_SCRIPT="$REPTY_EXT_DIR/semantic_search.py"
  cat > "$SEARCH_SCRIPT" <<'PYTHON'
import sys
import sqlite3
from sentence_transformers import SentenceTransformer
import numpy as np

# Load model
model = SentenceTransformer('all-MiniLM-L6-v2')

# Get query from command line
db_path = sys.argv[1]
query = ' '.join(sys.argv[2:])

# Generate embedding for query
query_embedding = model.encode(query)
query_embedding_bytes = np.array(query_embedding).tobytes()

# Connect to database
conn = sqlite3.connect(db_path)
conn.create_function('cosine_similarity', 2, lambda x, y: 
                     np.dot(np.frombuffer(x, dtype=np.float32), 
                            np.frombuffer(y, dtype=np.float32)) / 
                     (np.linalg.norm(np.frombuffer(x, dtype=np.float32)) * 
                      np.linalg.norm(np.frombuffer(y, dtype=np.float32))))

cursor = conn.cursor()

# Search for similar commands
cursor.execute('''
SELECT c.id, c.command, c.timestamp, c.cwd, c.exit_code, 
       cosine_similarity(e.embedding, ?) as similarity
FROM commands c
JOIN command_embeddings e ON c.id = e.command_id
ORDER BY similarity DESC
LIMIT 20
''', (query_embedding_bytes,))

results = cursor.fetchall()

# Print results in a format that can be parsed by the shell script
for result in results:
    cmd_id, cmd, timestamp, cwd, exit_code, similarity = result
    # Format: ID|TIMESTAMP|CWD|COMMAND|EXIT_CODE|SIMILARITY
    print(f"{cmd_id}|{timestamp}|{cwd}|{cmd}|{exit_code}|{similarity:.4f}")

conn.close()
PYTHON

  echo "Generating embeddings for existing commands..."
  python3 "$EMBED_SCRIPT" "$DB"
  
  WRAPPER_SCRIPT="$REPTY_EXT_DIR/semantic_search.sh"
  cat > "$WRAPPER_SCRIPT" <<EOF
#!/bin/bash

DB="\$HOME/.repty.db"
QUERY="\$*"

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Run semantic search
python3 "$SEARCH_SCRIPT" "\$DB" "\$QUERY" | while IFS='|' read -r id timestamp cwd command exit_code similarity; do
  # Format the output
  printf "%-19s | %-50s | %s (%.2f)\n" "\$timestamp" "\$command" "\$cwd" "\$similarity"
done
EOF

  chmod +x "$WRAPPER_SCRIPT"
  
  echo ""
  echo "Advanced NLP capabilities installed!"
  echo "You can now use more natural language queries with repty nlp."
  echo "Example: repty nlp \"show me git commands that failed recently\""
  
  exit 0
fi

if [ -f "$REPTY_EXT_DIR/semantic_search.sh" ] && [ $? -ne 0 ]; then
  echo ""
  echo "Trying semantic search..."
  "$REPTY_EXT_DIR/semantic_search.sh" "$QUERY"
fi 