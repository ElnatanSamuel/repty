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

# Color definitions
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC="\033[0m" # No Color

# Print step with color
print_step() {
    echo -e "${GREEN}▶${NC} $1"
}

# Create installation directory structure
print_step "Creating installation directory structure..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/lib/ext"

# Copy files to installation directory
print_step "Copying files to installation directory..."
# Check each critical file before copying
if [ -f "bin/repty" ]; then
    cp bin/repty "$INSTALL_DIR/bin/" || echo -e "${YELLOW}Warning:${NC} Could not copy repty binary"
else
    echo -e "${YELLOW}Warning:${NC} bin/repty not found in source directory"
fi

if [ -f "repty.sh" ]; then
    cp repty.sh "$INSTALL_DIR/" || echo -e "${YELLOW}Warning:${NC} Could not copy repty.sh"
else
    echo -e "${YELLOW}Warning:${NC} repty.sh not found in source directory"
fi

# Create cmdlog script if it doesn't exist
if [ ! -f "$INSTALL_DIR/bin/cmdlog" ]; then
    print_step "Creating command logging script..."
    cat > "$INSTALL_DIR/bin/cmdlog" << 'EOF'
#!/bin/bash
# Simple command logging script
REPTY_DB_PATH="$HOME/.repty.db"
echo "$(date +"%Y-%m-%d %H:%M:%S") | $PWD | $@" >> "$REPTY_DB_PATH"
"$@"
EOF
    chmod +x "$INSTALL_DIR/bin/cmdlog"
fi

# Copy library files
if [ -d "lib" ]; then
    # Copy each directory separately to avoid errors
    for file in lib/*.sh; do
        if [ -f "$file" ]; then
            cp "$file" "$INSTALL_DIR/lib/" || echo -e "${YELLOW}Warning:${NC} Could not copy $file"
            chmod +x "$INSTALL_DIR/lib/$(basename "$file")" 2>/dev/null
        fi
    done
    
    # Copy extension files
    if [ -d "lib/ext" ]; then
        for file in lib/ext/*.py; do
            if [ -f "$file" ]; then
                cp "$file" "$INSTALL_DIR/lib/ext/" || echo -e "${YELLOW}Warning:${NC} Could not copy $file"
                chmod +x "$INSTALL_DIR/lib/ext/$(basename "$file")" 2>/dev/null
            fi
        done
    else
        echo -e "${YELLOW}Warning:${NC} lib/ext directory not found"
    fi
else
    echo -e "${YELLOW}Warning:${NC} lib directory not found"
fi

# Make sure all script files are executable
print_step "Setting executable permissions..."
find "$INSTALL_DIR" -name "*.sh" -type f -exec chmod +x {} \;
find "$INSTALL_DIR" -name "*.py" -type f -exec chmod +x {} \;

echo -e "${GREEN}✓${NC} Repty installed to $INSTALL_DIR"

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
    print_step "Updating shell configuration..."
    echo -e "\n# Initialize repty command history manager" >> "$SHELL_CONFIG"
    echo "export REPTY_DIR=\"$INSTALL_DIR\"" >> "$SHELL_CONFIG"
    echo "source \$REPTY_DIR/repty.sh" >> "$SHELL_CONFIG"
    echo -e "${GREEN}✓${NC} Added repty initialization to $SHELL_CONFIG"
    echo "Please restart your shell or run 'source $SHELL_CONFIG' to apply changes"
else
    echo -e "${GREEN}✓${NC} Repty initialization already exists in $SHELL_CONFIG"
fi

# Check for required Python packages
if command -v pip3 &>/dev/null; then
    print_step "Checking for required Python packages..."
    
    # Check for scikit-learn (preferred) or sentence-transformers
    if ! python3 -c "import sklearn" &>/dev/null; then
        echo "scikit-learn not found, attempting to install..."
        pip3 install --user scikit-learn || echo -e "${YELLOW}Warning:${NC} scikit-learn installation failed. NLP search may use fallback methods."
    else
        echo -e "${GREEN}✓${NC} scikit-learn is already installed."
    fi
    
    # If scikit-learn failed, try sentence-transformers as fallback
    if ! python3 -c "import sklearn" &>/dev/null; then
        if ! python3 -c "import sentence_transformers" &>/dev/null; then
            echo "sentence-transformers not found, attempting to install..."
            pip3 install --user sentence-transformers || echo -e "${YELLOW}Warning:${NC} sentence-transformers installation failed. NLP search may not work."
        else
            echo -e "${GREEN}✓${NC} sentence-transformers is already installed."
        fi
    fi
else
    echo -e "${YELLOW}Warning:${NC} pip3 not found. Cannot install required Python packages."
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

# Ensure bootstrap script exists
if [ -f "$INSTALL_DIR/lib/bootstrap.sh" ]; then
    print_step "Running bootstrap script..."
    chmod +x "$INSTALL_DIR/lib/bootstrap.sh"
    "$INSTALL_DIR/lib/bootstrap.sh" || echo -e "${YELLOW}Warning:${NC} Bootstrap script failed"
else
    echo -e "${YELLOW}Warning:${NC} Bootstrap script not found at $INSTALL_DIR/lib/bootstrap.sh"
    
    # Create a basic placeholder bootstrap script if missing
    print_step "Creating basic bootstrap script..."
    cat > "$INSTALL_DIR/lib/bootstrap.sh" << 'EOF'
#!/bin/bash
# Basic bootstrap script
echo "Initializing repty..."
mkdir -p "$HOME/.repty.db.index"
touch "$HOME/.repty.db"
EOF
    chmod +x "$INSTALL_DIR/lib/bootstrap.sh"
    "$INSTALL_DIR/lib/bootstrap.sh"
fi

echo -e "${GREEN}✓${NC} Repty installation complete!"
echo "Run 'repty find <text>' to search your command history"
echo "Run 'repty nlp <query>' for natural language search"
