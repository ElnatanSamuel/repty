#!/bin/bash

# Check if REPTY_DIR is set, if not, default to ~/.repty
REPTY_DIR="${REPTY_DIR:-$HOME/.repty}"
REPTY_DB="${REPTY_DB:-$HOME/.repty.db}"
REPTY_HISTORY_FILE="${REPTY_HISTORY_FILE:-$HOME/.zsh_history}"

# Path to the SQLite database
DB_PATH="$REPTY_DB"

# Function to log commands to database
log_command() {
    local COMMAND="$1"
    local CODE="$2"
    
    # Skip logging if the command is empty or if it starts with a space
    if [[ -z "$COMMAND" || "$COMMAND" =~ ^\s ]]; then
        return
    fi
    
    # Skip logging if the command is itself a repty command
    if [[ "$COMMAND" == repty* ]]; then
        return
    fi
    
    # Use the repty command-line tool to log the command with keyword extraction
    "$REPTY_DIR/bin/repty" log "$CODE" "$COMMAND"
}

# Function to be called when a command is about to be executed
preexec() {
    REPTY_COMMAND_START=$(date +%s.%N)
    REPTY_CURRENT_COMMAND="$1"
}

# Function to be called after a command has been executed
precmd() {
    local CODE="$?"
    local COMMAND="$REPTY_CURRENT_COMMAND"
    
    if [ -n "$COMMAND" ]; then
        log_command "$COMMAND" "$CODE"
        unset REPTY_CURRENT_COMMAND
    fi
}

# Setup for bash
if [ -n "$BASH_VERSION" ]; then
    # Set up trap for DEBUG signal which is emitted before every command
    trap 'preexec "$BASH_COMMAND"' DEBUG
    
    # Set up PROMPT_COMMAND which is executed before each primary prompt
    PROMPT_COMMAND="precmd"
    
# Setup for zsh
elif [ -n "$ZSH_VERSION" ]; then
    # Check if the precmd_functions array exists
    if [[ ! -v precmd_functions ]]; then
        precmd_functions=()
    fi
    
    # Check if the preexec_functions array exists
    if [[ ! -v preexec_functions ]]; then
        preexec_functions=()
    fi
    
    # Add our functions to the arrays if they aren't already there
    if [[ ${precmd_functions[(ie)precmd]} -gt ${#precmd_functions} ]]; then
        precmd_functions+=(precmd)
    fi
    
    if [[ ${preexec_functions[(ie)preexec]} -gt ${#preexec_functions} ]]; then
        preexec_functions+=(preexec)
    fi
else
    echo "Unsupported shell. Only bash and zsh are supported."
    return 1
fi

# Initialize repty database if it doesn't exist
if [ ! -f "$DB_PATH" ]; then
    # Create database directory if it doesn't exist
    DB_DIR=$(dirname "$DB_PATH")
    if [ ! -d "$DB_DIR" ]; then
        mkdir -p "$DB_DIR"
    fi
    
    # Initialize the SQLite database with the schema
    "$REPTY_DIR/lib/bootstrap.sh"
fi

# Enable NLP search if available
if [ -f "$REPTY_DIR/lib/ext/semantic_search.py" ]; then
    touch "$REPTY_DIR/lib/ext/.nlp_enabled"
fi

# Set up PATH to include repty binaries
export PATH="$REPTY_DIR/bin:$PATH" 