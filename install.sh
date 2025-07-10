#!/bin/bash

# Default installation directory
INSTALL_DIR="$HOME/.repty"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--dir) INSTALL_DIR="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Create installation directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Copy files to installation directory
cp -r bin lib repty.sh "$INSTALL_DIR/"

echo "Repty installed to $INSTALL_DIR"

# Set up environment variables in shell config
SHELL_CONFIG=""
if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
else
    echo "Unsupported shell. Please manually add the following to your shell config:"
    echo "source $INSTALL_DIR/repty.sh"
    exit 1
fi

# Check if repty.sh is already sourced in shell config
if ! grep -q "source.*repty\.sh" "$SHELL_CONFIG"; then
    echo -e "\n# Initialize repty command history manager" >> "$SHELL_CONFIG"
    echo "export REPTY_DIR=\"$INSTALL_DIR\"" >> "$SHELL_CONFIG"
    echo "source \$REPTY_DIR/repty.sh" >> "$SHELL_CONFIG"
    echo "Added repty initialization to $SHELL_CONFIG"
    echo "Please restart your shell or run 'source $SHELL_CONFIG' to apply changes"
else
    echo "Repty initialization already exists in $SHELL_CONFIG"
fi

# Check for required Python packages
if command -v pip3 &>/dev/null; then
    echo "Checking for required Python packages..."
    
    # Check for scikit-learn (preferred) or sentence-transformers
    if ! python3 -c "import sklearn" &>/dev/null; then
        echo "scikit-learn not found, attempting to install..."
        pip3 install --user scikit-learn || echo "Warning: scikit-learn installation failed. NLP search may use fallback methods."
    else
        echo "scikit-learn is already installed."
    fi
    
    # If scikit-learn failed, try sentence-transformers as fallback
    if ! python3 -c "import sklearn" &>/dev/null; then
        if ! python3 -c "import sentence_transformers" &>/dev/null; then
            echo "sentence-transformers not found, attempting to install..."
            pip3 install --user sentence-transformers || echo "Warning: sentence-transformers installation failed. NLP search may not work."
        else
            echo "sentence-transformers is already installed."
        fi
    fi
else
    echo "Warning: pip3 not found. Cannot install required Python packages."
    echo "For NLP search functionality, please install scikit-learn or sentence-transformers manually:"
    echo "pip install scikit-learn"
    echo "or"
    echo "pip install sentence-transformers"
fi

# Initialize the database
DB_PATH="$HOME/.repty.db"
DB_DIR=$(dirname "$DB_PATH")

if [ ! -d "$DB_DIR" ]; then
    mkdir -p "$DB_DIR"
fi

# Run bootstrap script
"$INSTALL_DIR/lib/bootstrap.sh"

echo "Repty installation complete!"
echo "Run 'repty find <text>' to search your command history"
echo "Run 'repty nlp <query>' for natural language search"
