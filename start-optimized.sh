#!/bin/bash
set -e

# Configuration
COMFYUI_PATH="/opt/comfyui-base/ComfyUI"  # ComfyUI runs from here (never changes)
WORKSPACE_DIR="/workspace"  # RunPod persistent volume
ARGS_FILE="$WORKSPACE_DIR/comfyui_args.txt"
MODELS_DIR="$WORKSPACE_DIR/models"
OUTPUT_DIR="$WORKSPACE_DIR/output"
INPUT_DIR="$WORKSPACE_DIR/input"

# Performance optimizations for RunPod
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export CUDA_MODULE_LOADING=LAZY
export TOKENIZERS_PARALLELISM=false

# Don't activate venv here - we'll do it after checking if ComfyUI exists

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                  #
# ---------------------------------------------------------------------------- #

# Setup SSH with minimal writes
setup_ssh() {
    echo "Setting up SSH..."
    
    # Generate host keys in memory if they don't exist
    for type in rsa dsa ecdsa ed25519; do
        if [ ! -f "/etc/ssh/ssh_host_${type}_key" ]; then
            ssh-keygen -t ${type} -f "/etc/ssh/ssh_host_${type}_key" -q -N '' &
        fi
    done
    
    # Handle SSH authentication
    if [[ $PUBLIC_KEY ]]; then
        mkdir -p ~/.ssh
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh
    else
        RANDOM_PASS=$(openssl rand -base64 12)
        echo "root:${RANDOM_PASS}" | chpasswd
        echo "SSH password for root: ${RANDOM_PASS}"
    fi
    
    # Wait for key generation
    wait
    
    # Start SSH
    /usr/sbin/sshd
}

# Start services in parallel
start_services() {
    echo "Starting services..."
    
    # Start Zasper on port 8048
    echo "Starting Zasper on port 8048..."
    nohup zasper --port 0.0.0.0:8048 --cwd / &> /zasper.log &
    
    # Start Jupyter on port 8888
    echo "Starting Jupyter on port 8888..."
    cd / && \
    nohup jupyter lab --allow-root --no-browser --port=8888 --ip=* --NotebookApp.token='' --NotebookApp.password='' --FileContentsManager.delete_to_trash=False --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' --ServerApp.allow_origin=* --ServerApp.preferred_dir="$WORKSPACE_DIR" &> /jupyter.log &
    
    # Start FileBrowser (simple approach without database)
    echo "Starting FileBrowser on port 8080..."
    # Remove any existing database that might be corrupted
    rm -f "$WORKSPACE_DIR/.filebrowser.db" 2>/dev/null || true
    
    # Run FileBrowser directly without database (stateless mode)
    nohup filebrowser \
        --address 0.0.0.0 \
        --port 8080 \
        --root /workspace \
        --noauth \
        --log stdout &> /filebrowser.log &
    
    echo "Services started on ports: SSH(22), Zasper(8048), FileBrowser(8080), Jupyter(8888)"
}

# Setup workspace directories for models/outputs
setup_workspace() {
    echo "Setting up workspace directories..."
    
    # Create workspace directories for persistent data
    mkdir -p "$MODELS_DIR" "$OUTPUT_DIR" "$INPUT_DIR"
    mkdir -p "$WORKSPACE_DIR/temp" "$WORKSPACE_DIR/cache"
    
    # Create ComfyUI model subdirectories if they don't exist
    mkdir -p "$MODELS_DIR"/{checkpoints,loras,vae,controlnet,clip,unet,embeddings,hypernetworks,upscale_models}
    
    # Create symlinks from ComfyUI to workspace for persistent storage
    # This way ComfyUI uses /workspace for all user data
    for dir in models output input; do
        # Remove existing directory if it's not a symlink
        if [ -d "$COMFYUI_PATH/$dir" ] && [ ! -L "$COMFYUI_PATH/$dir" ]; then
            echo "Removing default $dir directory..."
            rm -rf "$COMFYUI_PATH/$dir"
        fi
        
        # Create symlink if it doesn't exist
        if [ ! -L "$COMFYUI_PATH/$dir" ]; then
            echo "Linking $COMFYUI_PATH/$dir -> $WORKSPACE_DIR/$dir"
            ln -sf "$WORKSPACE_DIR/$dir" "$COMFYUI_PATH/$dir"
        fi
    done
    
    # Create persistent directories for workflows and user data
    mkdir -p "$WORKSPACE_DIR/user" "$WORKSPACE_DIR/web" "$WORKSPACE_DIR/workflows" "$WORKSPACE_DIR/logs"
    
    # Symlink user directory (contains ComfyUI-Manager config, workflows, etc.)
    if [ -d "$COMFYUI_PATH/user" ] && [ ! -L "$COMFYUI_PATH/user" ]; then
        echo "Backing up existing user directory..."
        cp -r "$COMFYUI_PATH/user/"* "$WORKSPACE_DIR/user/" 2>/dev/null || true
        rm -rf "$COMFYUI_PATH/user"
    fi
    if [ ! -L "$COMFYUI_PATH/user" ]; then
        echo "Linking $COMFYUI_PATH/user -> $WORKSPACE_DIR/user"
        ln -sf "$WORKSPACE_DIR/user" "$COMFYUI_PATH/user"
    fi
    
    # Symlink web directory (contains workflows and UI state)
    if [ -d "$COMFYUI_PATH/web" ] && [ ! -L "$COMFYUI_PATH/web" ]; then
        echo "Backing up existing web directory..."
        cp -r "$COMFYUI_PATH/web/"* "$WORKSPACE_DIR/web/" 2>/dev/null || true
        rm -rf "$COMFYUI_PATH/web"
    fi
    if [ ! -L "$COMFYUI_PATH/web" ]; then
        echo "Linking $COMFYUI_PATH/web -> $WORKSPACE_DIR/web"  
        ln -sf "$WORKSPACE_DIR/web" "$COMFYUI_PATH/web"
    fi
    
    # Symlink ComfyUI logs for debugging persistence
    if [ -f "$COMFYUI_PATH/comfyui.log" ] && [ ! -L "$COMFYUI_PATH/comfyui.log" ]; then
        echo "Backing up existing log file..."
        cp "$COMFYUI_PATH/comfyui.log" "$WORKSPACE_DIR/logs/" 2>/dev/null || true
        rm -f "$COMFYUI_PATH/comfyui.log"
    fi
    if [ ! -L "$COMFYUI_PATH/comfyui.log" ]; then
        echo "Linking $COMFYUI_PATH/comfyui.log -> $WORKSPACE_DIR/logs/comfyui.log"
        ln -sf "$WORKSPACE_DIR/logs/comfyui.log" "$COMFYUI_PATH/comfyui.log"
    fi
    
    # Create temp directory symlink for faster I/O
    if [ ! -L "$COMFYUI_PATH/temp" ]; then
        ln -sf /tmp "$COMFYUI_PATH/temp"
    fi
    
    echo "Workspace setup complete. All user data will be saved to $WORKSPACE_DIR"
    
    # Download popular model if none exist (optional - comment out if not needed)
    if [ -z "$(ls -A $MODELS_DIR/checkpoints 2>/dev/null)" ]; then
        echo "No models found. To get started quickly, download a model to $MODELS_DIR/checkpoints/"
        # Uncomment to auto-download a small model:
        # cd "$MODELS_DIR/checkpoints" && \
        # wget -q --show-progress https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned.safetensors
    fi
}

# Export environment variables efficiently
export_env_vars() {
    # Only export critical RunPod variables
    printenv | grep -E '^RUNPOD_|^CUDA|^PATH=' | while read -r line; do
        export "$line"
    done
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                     #
# ---------------------------------------------------------------------------- #

echo "=== ComfyUI Startup ==="
echo "ComfyUI location: $COMFYUI_PATH"
echo "Workspace (persistent): $WORKSPACE_DIR"

# Run all setup in parallel
setup_ssh &
SSH_PID=$!

start_services &
SERVICES_PID=$!

setup_workspace &
WORKSPACE_PID=$!

export_env_vars &
ENV_PID=$!

# Wait for all parallel tasks
wait $SSH_PID $SERVICES_PID $WORKSPACE_PID $ENV_PID

# Create args file if it doesn't exist
if [ ! -f "$ARGS_FILE" ]; then
    cat > "$ARGS_FILE" << 'EOF'
# ComfyUI Arguments
# Add custom arguments below (one per line)
# Examples:
#   --highvram
#   --preview-method auto
#   --use-pytorch-cross-attention
EOF
fi

# Change to ComfyUI directory
cd "$COMFYUI_PATH"
echo "Working directory: $(pwd)"

# Activate the venv now that we know ComfyUI exists
if [ -f "$COMFYUI_PATH/.venv/bin/activate" ]; then
    echo "Activating ComfyUI virtual environment..."
    source "$COMFYUI_PATH/.venv/bin/activate"
    echo "Python path: $(which python)"
    echo "Python version: $(python --version)"
else
    echo "Warning: Virtual environment not found, using system Python"
    echo "Python path: $(which python3)"
    echo "Python version: $(python3 --version)"
fi

# Parse arguments
FIXED_ARGS="--listen 0.0.0.0 --port 8188"

# Auto-detect GPU and optimize settings
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
if [[ "$GPU_NAME" == *"4090"* ]] || [[ "$GPU_NAME" == *"5090"* ]]; then
    echo "Detected high-end GPU: $GPU_NAME"
    FIXED_ARGS="$FIXED_ARGS --highvram"
elif [[ "$GPU_NAME" == *"T4"* ]] || [[ "$GPU_NAME" == *"L4"* ]]; then
    echo "Detected cloud GPU: $GPU_NAME"
    FIXED_ARGS="$FIXED_ARGS --normalvram --use-pytorch-cross-attention"
fi

if [ -s "$ARGS_FILE" ]; then
    CUSTOM_ARGS=$(grep -v '^#' "$ARGS_FILE" 2>/dev/null | tr '\n' ' ')
    FINAL_ARGS="$FIXED_ARGS $CUSTOM_ARGS"
else
    FINAL_ARGS="$FIXED_ARGS"
fi

echo "Starting ComfyUI with args: $FINAL_ARGS"
echo "Models directory: $MODELS_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "GPU: $GPU_NAME"
echo "----------------------------------------"
echo ""
echo "🚀 ComfyUI is starting up..."
echo "📦 This may take 1-2 minutes on first launch while downloading registry data"
echo "🌐 Web interface will be available at: http://localhost:8188"
echo "⏳ Please wait for 'All startup tasks have been completed' message"
echo "----------------------------------------"

# Check current directory
echo "Current directory: $(pwd)"
echo "Contents of current directory:"
ls -la | head -10

# Run ComfyUI directly (no nohup, no background, direct output)
echo "Launching ComfyUI..."
echo "Command: python main.py $FINAL_ARGS"

# Check if we're in the right directory
if [ ! -f "main.py" ]; then
    echo "ERROR: main.py not found in $(pwd)"
    echo "Trying to find ComfyUI..."
    find /workspace -name "main.py" -type f 2>/dev/null | head -5
    find /opt -name "main.py" -type f 2>/dev/null | head -5
    exit 1
fi

# Use the right Python command
if [ -f "$COMFYUI_PATH/.venv/bin/python" ]; then
    echo "Using venv Python from $COMFYUI_PATH/.venv/bin/python"
    exec python main.py $FINAL_ARGS
else
    echo "Using system Python3"
    exec python3 main.py $FINAL_ARGS
fi