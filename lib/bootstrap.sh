#!/bin/bash

DB="$HOME/.repty.db"
REPTY_EXT_DIR="$(dirname "$(realpath "$0")")/ext"
mkdir -p "$REPTY_EXT_DIR"

if ! command -v sqlite3 &>/dev/null; then
  echo "SQLite3 not found. Attempting to install..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt update && sudo apt install -y sqlite3
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install sqlite
  else
    echo "Unsupported OS. Please install sqlite3 manually."
    exit 1
  fi
fi

sqlite3 "$DB" <<'EOF'
CREATE TABLE IF NOT EXISTS commands (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  command TEXT,
  timestamp TEXT,
  cwd TEXT,
  exit_code INTEGER,
  git_project TEXT,
  session_id TEXT,
  keywords TEXT
);

CREATE TABLE IF NOT EXISTS command_embeddings (
  command_id INTEGER PRIMARY KEY,
  embedding BLOB,
  FOREIGN KEY (command_id) REFERENCES commands(id)
);
EOF

# Add keywords column if it doesn't exist (for existing installations)
sqlite3 "$DB" "PRAGMA table_info(commands);" | grep -q "keywords" || \
  sqlite3 "$DB" "ALTER TABLE commands ADD COLUMN keywords TEXT;"

# Create Python scripts for advanced NLP
mkdir -p "$REPTY_EXT_DIR"

cat > "$REPTY_EXT_DIR/generate_embeddings.py" << 'EOF'
import sys
import os
import sqlite3
import numpy as np

try:
    from sentence_transformers import SentenceTransformer
except ImportError:
    print("Error: sentence-transformers package not found.")
    print("Please install it with: pip install sentence-transformers")
    sys.exit(1)

# Get database path from environment or use default
db_path = os.environ.get('REPTY_DB', os.path.expanduser('~/.repty.db'))

# Load a lightweight model
try:
    model = SentenceTransformer('all-MiniLM-L6-v2')
except Exception as e:
    print(f"Error loading model: {e}")
    sys.exit(1)

# Connect to database
try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
except Exception as e:
    print(f"Error connecting to database: {e}")
    sys.exit(1)

# Get commands without embeddings
try:
    cursor.execute('''
    SELECT id, command FROM commands 
    WHERE id NOT IN (SELECT command_id FROM command_embeddings)
    ''')
    
    commands = cursor.fetchall()
    
    if not commands:
        print("No new commands to process.")
        sys.exit(0)
        
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
    
    print("Embeddings generated and stored in database")
except Exception as e:
    print(f"Error generating embeddings: {e}")
    sys.exit(1)
finally:
    conn.close()
EOF

cat > "$REPTY_EXT_DIR/semantic_search.py" << 'EOF'
import sys
import os
import sqlite3
import numpy as np

try:
    from sentence_transformers import SentenceTransformer
except ImportError:
    print("Error: sentence-transformers package not found.")
    print("Please install it with: pip install sentence-transformers")
    sys.exit(1)

# Check arguments
if len(sys.argv) < 2:
    print("Usage: python semantic_search.py \"your query here\"")
    sys.exit(1)

# Get query from command line
query = ' '.join(sys.argv[1:])

# Get database path from environment or use default
db_path = os.environ.get('REPTY_DB', os.path.expanduser('~/.repty.db'))

# Load model - use a smaller model for faster inference
try:
    model = SentenceTransformer('all-MiniLM-L6-v2')
except Exception as e:
    print(f"Error loading model: {e}")
    sys.exit(1)

# Generate embedding for query
query_embedding = model.encode(query)
query_embedding_bytes = np.array(query_embedding).tobytes()

# Connect to database
try:
    conn = sqlite3.connect(db_path)
except Exception as e:
    print(f"Error connecting to database: {e}")
    sys.exit(1)

# Define cosine similarity function
def cosine_similarity(x, y):
    try:
        x_arr = np.frombuffer(x, dtype=np.float32)
        y_arr = np.frombuffer(y, dtype=np.float32)
        return float(np.dot(x_arr, y_arr) / (np.linalg.norm(x_arr) * np.linalg.norm(y_arr)))
    except:
        return 0.0

# Register the function with SQLite
conn.create_function("cosine_similarity", 2, cosine_similarity)

# Search for similar commands
try:
    cursor = conn.cursor()
    
    # Extract keywords from query to boost exact matches
    keywords = query.lower().split()
    keyword_conditions = ""
    if keywords:
        keyword_conditions = "OR " + " OR ".join([f"lower(c.command) LIKE '%{keyword}%'" for keyword in keywords])
    
    cursor.execute(f'''
    SELECT c.id, c.command, c.timestamp, c.cwd, c.exit_code, 
           cosine_similarity(e.embedding, ?) as similarity
    FROM commands c
    JOIN command_embeddings e ON c.id = e.command_id
    WHERE similarity > 0.5 {keyword_conditions}
    GROUP BY c.command
    ORDER BY similarity DESC
    LIMIT 10
    ''', (query_embedding_bytes,))
    
    results = cursor.fetchall()
    
    if not results:
        print("No similar commands found.")
        sys.exit(0)
    
    # Print results in a format that can be parsed by the shell script
    for result in results:
        cmd_id, cmd, timestamp, cwd, exit_code, similarity = result
        # Format: ID|TIMESTAMP|CWD|COMMAND|EXIT_CODE|SIMILARITY
        print(f"{cmd_id}|{timestamp}|{cwd}|{cmd}|{exit_code}|{similarity:.4f}")
        
except Exception as e:
    print(f"Error searching for similar commands: {e}")
    sys.exit(1)
finally:
    conn.close()
EOF

chmod +x "$REPTY_EXT_DIR/generate_embeddings.py"
chmod +x "$REPTY_EXT_DIR/semantic_search.py"

# Check if Python is available for advanced NLP features
if command -v python3 &>/dev/null; then
  echo "Python detected. Setting up advanced NLP capabilities..."
  
  # Check if pip is available
  if ! command -v pip3 &>/dev/null; then
    echo "Python pip not found. Installing required packages may fail."
    echo "On Ubuntu/Debian, install it with: sudo apt install python3-pip"
    echo "Basic NLP capabilities will be used for now."
    exit 0
  fi
  
  # Install only the required packages with minimal dependencies
  echo "Installing required Python packages..."
  pip3 install --user sentence-transformers==2.2.2 numpy --no-deps 2>/dev/null
  pip3 install --user torch==1.13.1 --no-deps 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo "Advanced NLP capabilities enabled!"
    touch "$REPTY_EXT_DIR/.nlp_enabled"
  else
    echo "Failed to install Python packages. Basic NLP capabilities will be used."
  fi
else
  echo "Python not found. Basic NLP capabilities will be used."
fi
