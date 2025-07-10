import sys
import os
import sqlite3
import numpy as np

# Force CPU-only mode for torch to avoid CUDA issues
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["NO_CUDA"] = "1"
os.environ["USE_TORCH"] = "0"  # Try to avoid torch if possible

def cosine_similarity_numpy(vec1, vec2):
    """Calculate cosine similarity between two vectors using numpy"""
    dot = np.dot(vec1, vec2)
    norm_a = np.linalg.norm(vec1)
    norm_b = np.linalg.norm(vec2)
    return dot / (norm_a * norm_b) if norm_a * norm_b > 0 else 0.0

def boost_score(command, base_score, key_terms, boost_factor):
    """Boost score if command contains key terms"""
    command_lower = command.lower()
    
    # Count how many key terms appear in the command
    matched_terms = sum(1 for term in key_terms if term in command_lower)
    
    # Define concept categories
    tool_terms = ['docker', 'git', 'npm', 'python', 'kubectl', 'terraform', 'ansible']
    db_terms = ['redis', 'postgres', 'mysql', 'mongodb', 'elasticsearch', 'cassandra']
    action_terms = ['run', 'start', 'stop', 'deploy', 'build', 'install', 'update', 'up', 'down']
    
    # Check if command contains terms from multiple concept categories
    has_tool = any(tool in command_lower for tool in tool_terms)
    has_db = any(db in command_lower for db in db_terms)
    has_action = any(action in command_lower for action in action_terms)
    
    # Calculate the concept boost based on category matches
    concept_boost = 1.0
    if (has_tool and has_db) or (has_tool and has_action) or (has_db and has_action):
        concept_boost = 1.5  # Boost for commands that combine concepts
        
    if has_tool and has_db and has_action:
        concept_boost = 2.0  # Extra boost for commands that combine all three concepts
    
    # Check if command contains all key terms - maximum boost
    if all(term in command_lower for term in key_terms) and key_terms:
        return base_score * boost_factor * 1.5 * concept_boost
    
    # If any terms match, boost based on how many match (more matches = higher boost)
    if matched_terms > 0:
        percentage_matched = matched_terms / len(key_terms) if key_terms else 0
        return base_score * (1 + percentage_matched * boost_factor) * concept_boost
        
    return base_score

def extract_key_terms(query):
    """Extract important key terms from the query"""
    # Split into words
    words = query.lower().split()
    
    # Important terms list - extensive list of tools, technologies, databases, etc.
    important_terms = [
        # Common command-line tools
        "git", "docker", "npm", "node", "python", "pip", "aws", "curl", "wget", 
        "ssh", "scp", "rsync", "tar", "zip", "unzip", "grep", "find", "sed", "awk",
        "head", "tail", "cat", "less", "more", "chmod", "chown", "mkdir", "rm", "cp",
        "mv", "ls", "ps", "kill", "systemctl", "service", "apt", "yum", "brew",
        "kubernetes", "k8s", "kubectl", "terraform", "ansible", "bash", "zsh", "fish",
        "vim", "emacs", "nano", "code", "make", "gcc", "clang", "javac", "go", "rust",
        
        # Common actions/verbs
        "start", "stop", "run", "install", "update", "remove", "create", "delete", "build",
        "deploy", "up", "down", "clone", "push", "pull", "commit", "checkout", "merge",
        "compose", "exec", "login", "logout", "config", "init", "test", "serve",
        
        # Databases and services
        "redis", "postgres", "postgresql", "mysql", "mongodb", "mongo", "db",
        "elasticsearch", "nginx", "apache", "tomcat", "wordpress", "rabbitmq",
        "kafka", "zookeeper", "cassandra", "memcached", "jenkins",
        
        # Cloud providers and tools
        "aws", "azure", "gcp", "google", "cloud", "ec2", "s3", "lambda",
        "terraform", "cloudformation", "heroku", "netlify", "vercel",
        
        # Frameworks and libraries
        "react", "vue", "angular", "svelte", "express", "flask", "django",
        "spring", "rails", "laravel", "dotnet", "tensorflow", "pytorch",
        "pandas", "numpy", "scikit", "jupyter", "notebook"
    ]
    
    # Multi-word phrases
    phrases = [
        "docker compose",
        "git commit",
        "git push",
        "git pull",
        "git clone",
        "npm install",
        "pip install"
    ]
    
    # Check for multi-word phrases
    key_terms = []
    query_lower = query.lower()
    
    # Look for phrases first
    for phrase in phrases:
        if phrase in query_lower:
            key_terms.append(phrase)
            # Also add individual components
            for word in phrase.split():
                if word not in key_terms and word in important_terms:
                    key_terms.append(word)
    
    # Add individual important terms
    for term in important_terms:
        if term in query_lower and term not in key_terms:
            key_terms.append(term)
    
    # Remove very short terms
    key_terms = [term for term in key_terms if len(term) > 1]
    
    return key_terms

# Try to use a simpler approach first
try:
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics.pairwise import cosine_similarity as sklearn_cosine
    
    USE_SCIKIT = True
    print("Using scikit-learn for semantic search", file=sys.stderr)
except ImportError:
    USE_SCIKIT = False
    print("scikit-learn not available, falling back to sentence-transformers", file=sys.stderr)
    try:
        # Import the SentenceTransformer class from sentence_transformers module
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

# Extract key terms from the query
key_terms = extract_key_terms(query)

try:
    print(f"DEBUG: Searching with query: {query}", file=sys.stderr)
    print(f"DEBUG: Key terms: {key_terms}", file=sys.stderr)
    
    # Check if keywords column exists in commands table
    cursor.execute("PRAGMA table_info(commands)")
    columns = [col[1] for col in cursor.fetchall()]
    
    # Get all commands to search through
    if 'keywords' in columns:
        cursor.execute("SELECT id, command, keywords FROM commands")
    else:
        cursor.execute("SELECT id, command FROM commands")
    
    all_commands = cursor.fetchall()
    
    if not all_commands:
        print("No commands found in database", file=sys.stderr)
        sys.exit(1)
    
    print(f"DEBUG: Found {len(all_commands)} commands to search", file=sys.stderr)
    
    # Prepare the text for each command
    command_texts = []
    command_ids = []
    
    for cmd in all_commands:
        cmd_id = cmd[0]
        command_text = cmd[1]
        
        # Include keywords if available
        if 'keywords' in columns and len(cmd) > 2 and cmd[2]:
            keywords = cmd[2]
            enriched_text = f"{command_text} {keywords} {keywords}"
        else:
            enriched_text = command_text
        
        command_texts.append(enriched_text)
        command_ids.append(cmd_id)
    
    # Get additional data for display
    id_to_data = {}
    cursor.execute("SELECT id, timestamp, cwd, exit_code FROM commands")
    for row in cursor.fetchall():
        id_to_data[row[0]] = (row[1], row[2], row[3])
    
    # Calculate similarity scores
    results = []
    
    if USE_SCIKIT:
        # Use TF-IDF for a simple but effective semantic search
        vectorizer = TfidfVectorizer(stop_words='english')
        try:
            tfidf_matrix = vectorizer.fit_transform(command_texts + [query])
            
            # Get the query vector (last one) and command vectors
            query_vector = tfidf_matrix[-1]
            command_vectors = tfidf_matrix[:-1]
            
            # Calculate similarities
            similarities = sklearn_cosine(query_vector, command_vectors)
            
            # Convert to list of (id, similarity) tuples
            for i, sim in enumerate(similarities[0]):
                cmd_id = command_ids[i]
                if cmd_id in id_to_data:
                    timestamp, cwd, exit_code = id_to_data[cmd_id]
                    results.append((
                        cmd_id, 
                        all_commands[i][1],  # command
                        timestamp, 
                        cwd, 
                        exit_code, 
                        float(sim)
                    ))
        except Exception as e:
            print(f"Error during TF-IDF calculation: {e}", file=sys.stderr)
            
    else:
        # Fallback to sentence-transformers
        try:
            model = SentenceTransformer('all-MiniLM-L6-v2', device="cpu")
            
            # Generate embeddings in smaller batches to avoid memory issues
            batch_size = 64
            all_embeddings = []
            
            for i in range(0, len(command_texts), batch_size):
                batch = command_texts[i:i+batch_size]
                embeddings = model.encode(batch)
                all_embeddings.extend(embeddings)
                
            query_embedding = model.encode(query)
            
            # Calculate similarities
            for i, cmd_embedding in enumerate(all_embeddings):
                cmd_id = command_ids[i]
                if cmd_id in id_to_data:
                    similarity = cosine_similarity_numpy(query_embedding, cmd_embedding)
                    timestamp, cwd, exit_code = id_to_data[cmd_id]
                    results.append((
                        cmd_id, 
                        all_commands[i][1],  # command
                        timestamp, 
                        cwd, 
                        exit_code, 
                        similarity
                    ))
        except Exception as e:
            print(f"Error during sentence-transformer encoding: {e}", file=sys.stderr)
    
    # Sort by similarity and boost commands that contain key terms
    boost_factor = 1.5
    results.sort(key=lambda x: boost_score(x[1], x[5], key_terms, boost_factor), reverse=True)
    
    # Take top 10 results
    top_results = results[:10]
    
    if not top_results:
        print("No similar commands found.")
        sys.exit(0)
    
    print(f"DEBUG: Found {len(top_results)} results", file=sys.stderr)
    
    # Print results in a format that can be parsed by the shell script
    for result in top_results:
        cmd_id, cmd, timestamp, cwd, exit_code, similarity = result
        # Format: ID|TIMESTAMP|CWD|COMMAND|EXIT_CODE|SIMILARITY
        print(f"{cmd_id}|{timestamp}|{cwd}|{cmd}|{exit_code}|{similarity:.4f}")
        
except Exception as e:
    print(f"Error searching for similar commands: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
finally:
    conn.close() 