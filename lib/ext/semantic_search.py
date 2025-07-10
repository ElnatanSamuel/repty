import sys
import os
import sqlite3
import numpy as np

# Force CPU-only mode for torch to avoid CUDA issues
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["NO_CUDA"] = "1"

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

# Connect to database
try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
except Exception as e:
    print(f"Error connecting to database: {e}", file=sys.stderr)
    sys.exit(1)

# Load model - use a smaller model for faster inference
try:
    model = SentenceTransformer('all-MiniLM-L6-v2', device="cpu")
except Exception as e:
    print(f"Error loading model: {e}", file=sys.stderr)
    sys.exit(1)

# Generate embedding for query
query_embedding = model.encode(query)
query_embedding_bytes = np.array(query_embedding).tobytes()

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

# Extract key terms from the query
query_terms = query.lower().split()
key_terms = []

# List of common command-line tools and concepts
important_terms = [
    "git", "docker", "npm", "node", "python", "pip", "aws", "curl", "wget", 
    "ssh", "scp", "rsync", "tar", "zip", "unzip", "grep", "find", "sed", "awk",
    "head", "tail", "cat", "less", "more", "chmod", "chown", "mkdir", "rm", "cp",
    "mv", "ls", "ps", "kill", "systemctl", "service", "apt", "yum", "brew",
    "kubernetes", "k8s", "kubectl", "terraform", "ansible", "bash", "zsh", "fish",
    "vim", "emacs", "nano", "code", "make", "gcc", "clang", "javac", "go", "rust"
]

# Extract important terms from the query
for term in query_terms:
    if term in important_terms:
        key_terms.append(term)

try:
    print(f"DEBUG: Searching with query: {query}", file=sys.stderr)
    print(f"DEBUG: Key terms: {key_terms}", file=sys.stderr)
    
    # Check if command_embeddings table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='command_embeddings'")
    if not cursor.fetchone():
        print("ERROR: command_embeddings table does not exist", file=sys.stderr)
        sys.exit(1)
        
    # Check if keywords column exists in commands table
    cursor.execute("PRAGMA table_info(commands)")
    columns = [col[1] for col in cursor.fetchall()]
    if 'keywords' not in columns:
        print("WARNING: keywords column does not exist in commands table", file=sys.stderr)
    
    # Count available embeddings
    cursor.execute("SELECT COUNT(*) FROM command_embeddings")
    count = cursor.fetchone()[0]
    print(f"DEBUG: Found {count} command embeddings", file=sys.stderr)
    
    # Build a query that balances semantic similarity with keyword matching
    base_query = '''
    SELECT c.id, c.command, c.timestamp, c.cwd, c.exit_code, 
           cosine_similarity(e.embedding, ?) as similarity
    FROM commands c
    JOIN command_embeddings e ON c.id = e.command_id
    '''
    
    # Add keyword boosting if we have key terms
    if key_terms:
        # Build keyword conditions for both command and keywords columns
        keyword_conditions = []
        for term in key_terms:
            keyword_conditions.append(f"lower(c.command) LIKE '%{term}%'")
            if 'keywords' in columns:  # Only add if keywords column exists
                keyword_conditions.append(f"lower(c.keywords) LIKE '%{term}%'")
        
        # Use the key terms to boost relevant results
        keyword_clause = " OR ".join(keyword_conditions)
        cursor.execute(f'''
        SELECT c.id, c.command, c.timestamp, c.cwd, c.exit_code,
               CASE 
                 WHEN ({keyword_clause}) THEN cosine_similarity(e.embedding, ?) * 2.0
                 ELSE cosine_similarity(e.embedding, ?)
               END as similarity
        FROM commands c
        JOIN command_embeddings e ON c.id = e.command_id
        WHERE similarity > 0.4
        GROUP BY c.command
        ORDER BY similarity DESC
        LIMIT 10
        ''', (query_embedding_bytes, query_embedding_bytes))
    else:
        # If no key terms, just use semantic similarity
        cursor.execute(f'''
        {base_query}
        WHERE similarity > 0.5
        GROUP BY c.command
        ORDER BY similarity DESC
        LIMIT 10
        ''', (query_embedding_bytes,))
    
    results = cursor.fetchall()
    
    # If no results, try a more relaxed search
    if not results:
        print("DEBUG: No results with first query, trying relaxed search", file=sys.stderr)
        cursor.execute(f'''
        {base_query}
        GROUP BY c.command
        ORDER BY similarity DESC
        LIMIT 5
        ''', (query_embedding_bytes,))
        results = cursor.fetchall()
    
    if not results:
        print("No similar commands found.")
        sys.exit(0)
    
    print(f"DEBUG: Found {len(results)} results", file=sys.stderr)
    
    # Print results in a format that can be parsed by the shell script
    for result in results:
        cmd_id = result[0]
        cmd = result[1]
        timestamp = result[2]
        cwd = result[3]
        exit_code = result[4]
        similarity = result[5]
        # Format: ID|TIMESTAMP|CWD|COMMAND|EXIT_CODE|SIMILARITY
        print(f"{cmd_id}|{timestamp}|{cwd}|{cmd}|{exit_code}|{similarity:.4f}")
        
except Exception as e:
    print(f"Error searching for similar commands: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
finally:
    conn.close() 