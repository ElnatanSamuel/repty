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

# Get database path from environment or use default
db_path = os.environ.get('REPTY_DB', os.path.expanduser('~/.repty.db'))

# Load a lightweight model
try:
    model = SentenceTransformer('all-MiniLM-L6-v2', device="cpu")
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

# Create command_embeddings table if it doesn't exist
try:
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS command_embeddings (
        command_id INTEGER PRIMARY KEY,
        embedding BLOB,
        FOREIGN KEY (command_id) REFERENCES commands(id)
    )
    ''')
    conn.commit()
except Exception as e:
    print(f"Error creating table: {e}")
    sys.exit(1)

# Check if keywords column exists in commands table
try:
    cursor.execute("PRAGMA table_info(commands)")
    columns = [col[1] for col in cursor.fetchall()]
    has_keywords = 'keywords' in columns
    print(f"Keywords column exists: {has_keywords}")
except Exception as e:
    print(f"Error checking table schema: {e}")
    has_keywords = False

# Get commands without embeddings
try:
    if has_keywords:
        cursor.execute('''
        SELECT id, command, keywords FROM commands 
        WHERE id NOT IN (SELECT command_id FROM command_embeddings)
        ''')
    else:
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
        
        # Use keywords if available to enrich the text for embedding
        texts = []
        for cmd in batch:
            command_text = cmd[1]
            
            if has_keywords and len(cmd) > 2:
                keywords = cmd[2] if cmd[2] else ""
                
                # Enrich text with keywords if available (repeated to give them more weight)
                if keywords:
                    enriched_text = f"{command_text} {keywords} {keywords}"
                else:
                    enriched_text = command_text
            else:
                enriched_text = command_text
                
            texts.append(enriched_text)
        
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
    import traceback
    traceback.print_exc()
    sys.exit(1)
finally:
    conn.close() 