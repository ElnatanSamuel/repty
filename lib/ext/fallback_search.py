#!/usr/bin/env python3
# Simple fallback search for when scikit-learn and sentence-transformers are not available

import sys
import os
import sqlite3
import re

def normalize_text(text):
    """Remove special characters and normalize whitespace"""
    if not text:
        return ""
    text = text.lower()
    text = re.sub(r'[^\w\s]', ' ', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def extract_keywords(query):
    """Extract important keywords from query"""
    query = normalize_text(query)
    words = query.split()
    
    # Filter out common stop words
    stop_words = {"the", "a", "an", "in", "on", "at", "to", "for", "with", 
                  "by", "about", "of", "from", "as", "this", "that", 
                  "and", "or", "but", "if", "when", "where", "how", 
                  "what", "which", "who", "whom", "whose", "why", 
                  "is", "are", "was", "were", "be", "been", "being", 
                  "have", "has", "had", "do", "does", "did", "i", 
                  "you", "he", "she", "they", "we", "it"}
    
    keywords = [word for word in words if word not in stop_words and len(word) > 1]
    return keywords

def calculate_score(command, keywords):
    """Calculate relevance score based on keyword matches"""
    if not keywords:
        return 0.0
    
    command_text = normalize_text(command)
    
    # Count how many keywords appear in the command
    matches = sum(1 for keyword in keywords if keyword in command_text)
    
    # Calculate score based on matches and proximity
    if matches == 0:
        return 0.0
    
    score = matches / len(keywords)
    
    # Boost for exact phrases
    for i in range(len(keywords) - 1):
        phrase = f"{keywords[i]} {keywords[i+1]}"
        if phrase in command_text:
            score += 0.2
    
    # Boost if all keywords are found
    if matches == len(keywords):
        score *= 1.5
    
    return min(score, 1.0)  # Cap score at 1.0

def main():
    # Check arguments
    if len(sys.argv) < 2:
        print("Usage: python fallback_search.py \"your query here\"")
        sys.exit(1)
    
    # Get query from command line
    query = ' '.join(sys.argv[1:])
    keywords = extract_keywords(query)
    
    # Get database path from environment or use default
    db_path = os.environ.get('REPTY_DB', os.path.expanduser('~/.repty.db'))
    
    try:
        # Connect to database
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get all commands
        cursor.execute("SELECT id, command, timestamp, cwd, exit_code FROM commands")
        all_commands = cursor.fetchall()
        
        # Calculate scores
        results = []
        for cmd in all_commands:
            cmd_id, command, timestamp, cwd, exit_code = cmd
            score = calculate_score(command, keywords)
            if score > 0:
                results.append((cmd_id, command, timestamp, cwd, exit_code, score))
        
        # Sort by score
        results.sort(key=lambda x: x[5], reverse=True)
        
        # Take top 10 results
        top_results = results[:10]
        
        # Print results
        for result in top_results:
            cmd_id, command, timestamp, cwd, exit_code, score = result
            print(f"{cmd_id}|{timestamp}|{cwd}|{command}|{exit_code}|{score:.4f}")
        
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    main() 