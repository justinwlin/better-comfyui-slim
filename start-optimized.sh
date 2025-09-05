#!/bin/bash
set -e

# Configuration - everything runs from baked-in locations
COMFYUI_PATH="/opt/comfyui-base/ComfyUI"
WORKSPACE_DIR="/workspace/madapps"
ARGS_FILE="$WORKSPACE_DIR/comfyui_args.txt"
MODELS_DIR="$WORKSPACE_DIR/models"
OUTPUT_DIR="$WORKSPACE_DIR/output"
INPUT_DIR="$WORKSPACE_DIR/input"

# Performance optimizations for RunPod
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
export CUDA_MODULE_LOADING=LAZY
export TOKENIZERS_PARALLELISM=false

# Activate the venv that contains all dependencies
source "$COMFYUI_PATH/.venv/bin/activate"

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
    nohup zasper --port 0.0.0.0:8048 --cwd /workspace &> /zasper.log &
    
    # Start Jupyter on port 8888
    echo "Starting Jupyter on port 8888..."
    nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' &> /jupyter.log &
    
    # Start FileBrowser (minimal config)
    if [ ! -f "$WORKSPACE_DIR/.filebrowser.db" ]; then
        # First run only - create minimal config
        filebrowser config init --database "$WORKSPACE_DIR/.filebrowser.db"
        filebrowser config set --address 0.0.0.0 --port 8080 --root /workspace --auth.method=noauth --database "$WORKSPACE_DIR/.filebrowser.db"
    fi
    nohup filebrowser --database "$WORKSPACE_DIR/.filebrowser.db" &> /dev/null &
    
    echo "Services started on ports: SSH(22), Zasper(8048), FileBrowser(8080), Jupyter(8888)"
}

# Setup workspace directories for models/outputs
setup_workspace() {
    echo "Setting up workspace..."
    
    # Create directories for user data
    mkdir -p "$MODELS_DIR" "$OUTPUT_DIR" "$INPUT_DIR"
    mkdir -p "$WORKSPACE_DIR/temp" "$WORKSPACE_DIR/cache"
    
    # Create symlinks from ComfyUI to workspace for models/output/input
    # This allows ComfyUI to use workspace storage for user data
    # while keeping the code in the image
    
    # Remove existing directories if they exist and create symlinks
    for dir in models output input; do
        if [ -d "$COMFYUI_PATH/$dir" ] && [ ! -L "$COMFYUI_PATH/$dir" ]; then
            # Move any existing files to workspace
            if [ "$(ls -A $COMFYUI_PATH/$dir 2>/dev/null)" ]; then
                echo "Moving existing $dir to workspace..."
                cp -r "$COMFYUI_PATH/$dir"/* "$WORKSPACE_DIR/$dir/" 2>/dev/null || true
            fi
            rm -rf "$COMFYUI_PATH/$dir"
        fi
        
        # Create symlink if it doesn't exist
        if [ ! -e "$COMFYUI_PATH/$dir" ]; then
            ln -s "$WORKSPACE_DIR/$dir" "$COMFYUI_PATH/$dir"
        fi
    done
    
    # Create temp directory symlink for faster I/O on temporary files
    if [ ! -L "$COMFYUI_PATH/temp" ]; then
        ln -s /tmp "$COMFYUI_PATH/temp" 2>/dev/null || true
    fi
    
    # Ensure ComfyUI workspace link exists (for compatibility)
    if [ ! -L "$WORKSPACE_DIR/ComfyUI" ]; then
        ln -s "$COMFYUI_PATH" "$WORKSPACE_DIR/ComfyUI" 2>/dev/null || true
    fi
    
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

echo "=== ComfyUI Optimized Startup (Minimal Writes) ==="
echo "ComfyUI is pre-installed at: $COMFYUI_PATH"

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

# Run ComfyUI directly (no nohup, no background, direct output)
exec python main.py $FINAL_ARGS