# syntax=docker/dockerfile:1.4

# Stage 1: Ubuntu base
FROM ubuntu:22.04 AS ubuntu-base
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: CUDA installation
FROM ubuntu-base AS cuda-install
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-12-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb

# Stage 3: Python and dev tools
FROM cuda-install AS python-install
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    && add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Stage 4: System tools
FROM python-install AS system-tools
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    curl \
    xz-utils \
    openssh-client \
    openssh-server \
    nano \
    htop \
    tmux \
    less \
    net-tools \
    iputils-ping \
    procps \
    golang \
    make \
    ffmpeg \
    rsync \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Stage 5: Setup Python and pip
FROM system-tools AS python-setup
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --set python3 /usr/bin/python3.12

ENV PYTHONUNBUFFERED=1
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}

# Stage 6: UV installation
FROM python-setup AS uv-install
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -U pip && \
    pip install --no-cache-dir uv

# Stage 7: PyTorch installation
FROM uv-install AS pytorch-install
RUN --mount=type=cache,target=/root/.cache/pip \
    uv pip install --system --no-cache \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Stage 8: Core ML libraries
FROM pytorch-install AS ml-libraries
RUN --mount=type=cache,target=/root/.cache/pip \
    uv pip install --system --no-cache \
    numpy \
    opencv-python \
    pillow \
    safetensors \
    xformers

# Stage 9: Transformers and diffusers
FROM ml-libraries AS transformers-install
RUN --mount=type=cache,target=/root/.cache/pip \
    uv pip install --system --no-cache \
    transformers \
    diffusers \
    accelerate

# Stage 10: Jupyter installation
FROM transformers-install AS jupyter-install
RUN --mount=type=cache,target=/root/.cache/pip \
    uv pip install --system --no-cache \
    jupyter \
    jupyterlab \
    notebook \
    ipywidgets

# Stage 11: ComfyUI base
FROM jupyter-install AS comfyui-base
RUN mkdir -p /root && \
    cd /root && \
    git clone https://github.com/comfyanonymous/ComfyUI.git

# Stage 12: ComfyUI requirements
FROM comfyui-base AS comfyui-deps
WORKDIR /root/ComfyUI
RUN --mount=type=cache,target=/root/.cache/pip \
    uv pip install --system --no-cache -r requirements.txt

# Stage 13: ComfyUI-Manager
FROM comfyui-deps AS comfyui-manager
RUN cd /root/ComfyUI && \
    mkdir -p custom_nodes && \
    cd custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    if [ -f "ComfyUI-Manager/requirements.txt" ]; then \
        uv pip install --system --no-cache -r ComfyUI-Manager/requirements.txt || true; \
    fi

# Stage 14: Other custom nodes
FROM comfyui-manager AS custom-nodes
RUN cd /root/ComfyUI/custom_nodes && \
    git clone https://github.com/crystian/ComfyUI-Crystools.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    for node_dir in */; do \
        if [ -d "$node_dir" ] && [ -f "$node_dir/requirements.txt" ]; then \
            uv pip install --system --no-cache -r "$node_dir/requirements.txt" || true; \
        fi; \
    done

# Stage 15: FileBrowser
FROM custom-nodes AS filebrowser
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Stage 16: Zasper
FROM filebrowser AS zasper
RUN wget https://github.com/zasper-io/zasper/releases/download/v0.1.0-alpha/zasper-webapp-linux-amd64.tar.gz && \
    tar xf zasper-webapp-linux-amd64.tar.gz -C /usr/local/bin && \
    rm zasper-webapp-linux-amd64.tar.gz

# Stage 17: Final configuration
FROM zasper AS final

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV FILEBROWSER_CONFIG=/workspace/madapps/.filebrowser.json
ENV COMFYUI_PATH=/root/ComfyUI

# Configure SSH for root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd

# Create workspace directory structure
RUN mkdir -p /workspace/madapps && \
    ln -s /root/ComfyUI /workspace/madapps/ComfyUI || true

# Set working directory
WORKDIR /root/ComfyUI

# Copy startup script
COPY start-optimized.sh /start.sh
RUN chmod +x /start.sh

# Expose ports for ComfyUI, SSH, Zasper, FileBrowser, and Jupyter
EXPOSE 8188 22 8048 8080 8888

ENTRYPOINT ["/start.sh"]