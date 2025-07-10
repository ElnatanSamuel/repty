import sys
import os
import sqlite3
import numpy as np

# Force CPU-only mode for torch to avoid CUDA issues
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["NO_CUDA"] = "1"
os.environ["USE_TORCH"] = "0"  # Try to avoid torch if possible

# Try to use scikit-learn if available
try:
    from sklearn.feature_extraction.text import TfidfVectorizer
    USE_SCIKIT = True
    print("Using scikit-learn for embeddings")
except ImportError:
    USE_SCIKIT = False
    print("scikit-learn not available, trying sentence-transformers")
    try:
        from sentence_transformers.SentenceTransformer import SentenceTransformer
    except ImportError:
        print("Error: Neither scikit-learn nor sentence-transformers package found.")
        print("Please install one of them: pip install scikit-learn or pip install sentence-transformers")
        
        # Create a flag file to indicate we attempted to generate embeddings
        # This prevents repeated attempts that will fail
        flag_file = os.path.join(os.path.dirname(os.path.realpath(__file__)), ".embeddings_processed")
        with open(flag_file, "w") as f:
            f.write("Embeddings processing attempted but dependencies missing")
        
        sys.exit(1)

# Get database path from environment or use default
db_path = os.environ.get('REPTY_DB', os.path.expanduser('~/.repty.db'))

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
        
        # Create flag file to indicate processing completed
        flag_file = os.path.join(os.path.dirname(os.path.realpath(__file__)), ".embeddings_processed")
        with open(flag_file, "w") as f:
            f.write("No new commands to process")
            
        sys.exit(0)
        
    print(f"Processing {len(commands)} commands...")
    
    # Prepare command texts and ids
    texts = []
    ids = []
    for cmd in commands:
        command_id = cmd[0]
        command_text = cmd[1]
        
        if has_keywords and len(cmd) > 2:
            keywords = cmd[2] if cmd[2] else ""
            
            # Enrich text with keywords if available
            if keywords:
                enriched_text = f"{command_text} {keywords} {keywords}"
            else:
                enriched_text = command_text
        else:
            enriched_text = command_text
        
        texts.append(enriched_text)
        ids.append(command_id)
    
    # Create embeddings based on available libraries
    success = False
    
    if USE_SCIKIT:
        try:
            # Create TF-IDF matrix
            vectorizer = TfidfVectorizer(stop_words='english')
            tfidf_matrix = vectorizer.fit_transform(texts)
            
            # Store each command's vector
            for i, cmd_id in enumerate(ids):
                vector = tfidf_matrix[i].toarray().flatten()
                embedding_bytes = np.array(vector, dtype=np.float32).tobytes()
                cursor.execute('INSERT INTO command_embeddings (command_id, embedding) VALUES (?, ?)',
                              (cmd_id, embedding_bytes))
            
            conn.commit()
            success = True
            print(f"Generated TF-IDF embeddings for {len(ids)} commands")
        except Exception as e:
            print(f"Error generating TF-IDF embeddings: {e}")
            import traceback
            traceback.print_exc()
    
    if not success and not USE_SCIKIT:
        try:
            # Load model
            model = SentenceTransformer('all-MiniLM-L6-v2', device="cpu")
            
            # Generate embeddings in batches
            batch_size = 32
            for i in range(0, len(texts), batch_size):
                batch_texts = texts[i:i+batch_size]
                batch_ids = ids[i:i+batch_size]
                
                # Generate embeddings
                embeddings = model.encode(batch_texts)
                
                # Store embeddings
                for j, embedding in enumerate(embeddings):
                    cmd_id = batch_ids[j]
                    # Convert numpy array to bytes
                    embedding_bytes = np.array(embedding).tobytes()
                    cursor.execute('INSERT INTO command_embeddings (command_id, embedding) VALUES (?, ?)',
                                (cmd_id, embedding_bytes))
            
            conn.commit()
            success = True
            print(f"Generated sentence-transformer embeddings for {len(ids)} commands")
        except Exception as e:
            print(f"Error generating sentence-transformer embeddings: {e}")
            import traceback
            traceback.print_exc()
    
    # Create flag file regardless of success to prevent repeated attempts
    flag_file = os.path.join(os.path.dirname(os.path.realpath(__file__)), ".embeddings_processed")
    with open(flag_file, "w") as f:
        if success:
            f.write(f"Successfully processed {len(ids)} commands")
        else:
            f.write("Attempted to process embeddings but encountered errors")
    
    if success:
        print("Embeddings generated and stored in database")
    else:
        print("Failed to generate embeddings. Keyword search will be used instead.")
        
except Exception as e:
    print(f"Error processing commands: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
finally:
    conn.close() 