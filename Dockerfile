# syntax=docker/dockerfile:1.4
# Multi-stage build for smaller final image
FROM ubuntu:22.04 AS base-system

ENV DEBIAN_FRONTEND=noninteractive

# Minimal system packages only
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    && add-apt-repository ppa:deadsnakes/ppa && \
    add-apt-repository ppa:cybermax-dexter/ffmpeg-nvenc && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    git \
    wget \
    curl \
    ca-certificates \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12

# Install pip
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# ============================================
# Build stage for ComfyUI
FROM base-system AS comfyui-builder

# Install build dependencies (will be discarded)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Clone and setup ComfyUI
RUN mkdir -p /opt/comfyui-base && \
    cd /opt && \
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git comfyui-base/ComfyUI && \
    rm -rf /opt/comfyui-base/ComfyUI/.git

# Create venv and install dependencies
RUN cd /opt/comfyui-base/ComfyUI && \
    python3.12 -m venv .venv && \
    . .venv/bin/activate && \
    pip install -U pip && \
    pip install uv && \
    # Install PyTorch with CUDA 12.4 support first
    uv pip install --no-cache torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 && \
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
# Build stage for custom nodes
FROM comfyui-builder AS custom-nodes-builder

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
# Build stage for external tools
FROM golang:1.21-alpine AS zasper-builder

RUN apk add --no-cache git
RUN wget https://github.com/zasper-io/zasper/releases/download/v0.1.0-alpha/zasper-webapp-linux-amd64.tar.gz && \
    tar xf zasper-webapp-linux-amd64.tar.gz

# ============================================
# Final minimal image
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV FILEBROWSER_CONFIG=/workspace/madapps/.filebrowser.json
ENV UV_LINK_MODE=copy
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}

# Install only runtime dependencies (no build tools)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    && add-apt-repository ppa:deadsnakes/ppa && \
    add-apt-repository ppa:cybermax-dexter/ffmpeg-nvenc && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    curl \
    ca-certificates \
    openssh-server \
    ffmpeg \
    rsync \
    # Minimal tools only
    nano \
    htop \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12

# Install pip and jupyter (small)
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 && \
    pip install --no-cache-dir jupyter && \
    pip cache purge

# Install CUDA (this is large but necessary)
RUN wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends cuda-minimal-build-12-4 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm cuda-keyring_1.1-1_all.deb

# Install FileBrowser (small binary)
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Copy Zasper from builder
COPY --from=zasper-builder /go/zasper /usr/local/bin/

# Configure SSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd

# Copy pre-built ComfyUI from builder stage
COPY --from=custom-nodes-builder /opt/comfyui-base /opt/comfyui-base

# Create workspace
RUN mkdir -p /workspace/madapps
WORKDIR /workspace/madapps

EXPOSE 8188 22 8048 8080 8888

# Copy start script
COPY start-optimized.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]