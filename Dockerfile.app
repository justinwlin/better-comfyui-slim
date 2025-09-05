# syntax=docker/dockerfile:1.4
# ComfyUI application layer
# Builds on top of base image that has CUDA, Python, and tools

# When using docker-bake.hcl, this uses the base target
# When building standalone, use: --build-context base-image=justinrunpod/ubuntu-cuda12.4-python3.12-uv:latest
FROM base-image AS comfyui-builder

# ============================================
# Build ComfyUI with virtual environment
# ============================================

# Clone and setup ComfyUI
RUN mkdir -p /opt/comfyui-base && \
    cd /opt && \
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git comfyui-base/ComfyUI && \
    rm -rf /opt/comfyui-base/ComfyUI/.git

# Create venv and install dependencies
WORKDIR /opt/comfyui-base/ComfyUI
RUN python3.12 -m venv .venv && \
    . .venv/bin/activate && \
    pip install -U pip && \
    pip install uv && \
    # Install PyTorch with CUDA 12.4 support first
    uv pip install --no-cache torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 && \
    uv pip install --no-cache -r requirements.txt && \
    uv pip install --no-cache GitPython numpy pillow opencv-python && \
    # Clean up pip cache
    pip cache purge && \
    # Remove unnecessary files from venv
    find .venv -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true && \
    find .venv -name "*.pyc" -delete && \
    find .venv -name "*.pyo" -delete && \
    rm -rf .venv/share/python-wheels && \
    rm -rf .venv/lib/python*/site-packages/*.dist-info/RECORD && \
    rm -rf .venv/lib/python*/site-packages/*.dist-info/INSTALLER

# ============================================
# Install custom nodes
# ============================================

FROM comfyui-builder AS custom-nodes

# Clone custom nodes with --depth 1 for smaller size
RUN cd /opt/comfyui-base/ComfyUI && \
    mkdir -p custom_nodes && \
    cd custom_nodes && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git && \
    # Remove .git directories to save space
    find . -type d -name ".git" -exec rm -rf {} + 2>/dev/null || true

# Install custom node dependencies
RUN cd /opt/comfyui-base/ComfyUI/custom_nodes && \
    . /opt/comfyui-base/ComfyUI/.venv/bin/activate && \
    for node_dir in */; do \
        if [ -d "$node_dir" ] && [ -f "$node_dir/requirements.txt" ]; then \
            uv pip install --no-cache -r "$node_dir/requirements.txt" || true; \
        fi; \
    done && \
    pip cache purge

# ============================================
# Final image
# ============================================

FROM base-image AS final

# ComfyUI-specific environment variable
ENV FILEBROWSER_CONFIG=/workspace/madapps/.filebrowser.json

# Copy pre-built ComfyUI to a safe location
COPY --from=custom-nodes /opt/comfyui-base /opt/comfyui-base

# Create workspace directory (will be overshadowed by RunPod mount)
RUN mkdir -p /workspace/madapps

WORKDIR /workspace/madapps

# Expose ports for all services
EXPOSE 8188 22 8048 8080 8888

# Copy start script
COPY --link start-optimized.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]