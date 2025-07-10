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

# Connect to database
try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
except Exception as e:
    print(f"Error connecting to database: {e}")
    sys.exit(1)

# Load model - use a smaller model for faster inference
try:
    model = SentenceTransformer('all-MiniLM-L6-v2')
except Exception as e:
    print(f"Error loading model: {e}")
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

# Try semantic search
try:
    # Build a query that balances semantic similarity with keyword matching
    base_query = '''
    SELECT c.id, c.command, c.timestamp, c.cwd, c.exit_code, c.keywords,
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
            keyword_conditions.append(f"lower(c.keywords) LIKE '%{term}%'")
        
        # Use the key terms to boost relevant results
        keyword_clause = " OR ".join(keyword_conditions)
        cursor.execute(f'''
        SELECT c.id, c.command, c.timestamp, c.cwd, c.exit_code, c.keywords,
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
    
    # Print results in a format that can be parsed by the shell script
    for result in results:
        cmd_id, cmd, timestamp, cwd, exit_code, keywords, similarity = result
        # Format: ID|TIMESTAMP|CWD|COMMAND|EXIT_CODE|SIMILARITY
        # Note: We're not including keywords in the output to maintain compatibility
        print(f"{cmd_id}|{timestamp}|{cwd}|{cmd}|{exit_code}|{similarity:.4f}")
        
except Exception as e:
    print(f"Error searching for similar commands: {e}")
    sys.exit(1)
finally:
    conn.close() 