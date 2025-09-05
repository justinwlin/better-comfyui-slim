# Better ComfyUI Slim

Optimized ComfyUI Docker image for RunPod with split-layer architecture for fast builds and deployments.

## 🚀 Quick Deploy on RunPod

[![Deploy on RunPod](https://img.shields.io/badge/Deploy%20on%20RunPod-ComfyUI-4B6BDC?style=for-the-badge&logo=docker)](https://runpod.io/console/deploy?template=cndsag8ob0&ref=vfker49t)

### Using Pre-built Images

If you just want to use the images without building:

```bash
# Pull and run ComfyUI (full descriptive name)
docker pull justinrunpod/ubuntu-cuda-comfyui:latest
docker run -p 8188:8188 justinrunpod/ubuntu-cuda-comfyui:latest

# Or use simple alias
docker pull justinrunpod/comfyui:latest
docker run -p 8188:8188 justinrunpod/comfyui:latest

# On RunPod - use either:
justinrunpod/ubuntu-cuda-comfyui:latest  # Clear what's included
justinrunpod/comfyui:latest              # Simple version
```

## 🏗️ Build Instructions

This project uses a two-layer Docker architecture for efficiency:
- **Base Image**: Ubuntu, CUDA, Python, tools (rarely changes)
- **App Image**: ComfyUI and custom nodes (frequently updated)

### Using Depot (Recommended - Cloud Build)

```bash
# Build everything in parallel and push
depot bake -f docker-bake.hcl --push

# Or build separately:
# Build only base image (when updating CUDA/tools)
depot bake -f docker-bake.hcl base-only --push

# Build only app image (when updating ComfyUI)
depot bake -f docker-bake.hcl app-only --push
```

### Using Docker Buildx (Local Build)

```bash
# Setup buildx (one time)
docker buildx create --name mybuilder --use

# Build and push everything
docker buildx bake -f docker-bake.hcl --push
```

### 📦 Where Images Are Pushed

By default, images are pushed to Docker Hub with descriptive names:

**Base Image** (General purpose Ubuntu + CUDA + Python):
- `justinrunpod/ubuntu-cuda-python:latest`
- `justinrunpod/ubuntu-cuda-python:ubuntu22.04-cuda12.4-python3.12`

**ComfyUI Image** (Full application):
- `justinrunpod/ubuntu-cuda-comfyui:latest`
- `justinrunpod/ubuntu-cuda-comfyui:ubuntu22.04-cuda12.4-python3.12-pytorch2.5.1`
- `justinrunpod/comfyui:latest` (simple alias)

To use your own registry:

```bash
# Docker Hub (default)
export REGISTRY=yourdockerhubusername
depot bake -f docker-bake.hcl --push

# GitHub Container Registry
export REGISTRY=ghcr.io/yourusername
depot bake -f docker-bake.hcl --push

# Custom Registry
export REGISTRY=your-registry.com/namespace
depot bake -f docker-bake.hcl --push
```

The image naming convention:
- **Base**: `ubuntu-cuda-python:ubuntu{VERSION}-cuda{VERSION}-python{VERSION}`
- **App**: `ubuntu-cuda-comfyui:ubuntu{VERSION}-cuda{VERSION}-python{VERSION}-pytorch{VERSION}`

## 📦 Architecture

### Two-Stage Build System

1. **Base Image** (`Dockerfile.base`) - ~2-3GB
   - Ubuntu 22.04
   - CUDA 12.4
   - Python 3.12
   - UV (deterministic package manager)
   - Jupyter, FileBrowser, Zasper
   - SSH server

2. **App Image** (`Dockerfile.app`) - ~4-5GB total
   - ComfyUI with virtual environment
   - PyTorch with CUDA support
   - Custom nodes (Manager, Crystools, KJNodes)
   - All Python dependencies

### Why This Architecture?

- **Fast Rebuilds**: Base rarely changes, only rebuild app layer
- **Efficient Caching**: Depot/Docker caches base image
- **Deterministic**: UV ensures same dependencies every build
- **Small Updates**: ComfyUI updates only rebuild ~1-2GB

## 🎯 Features

- **Instant Startup**: Everything pre-installed in image
- **Persistent Storage**: Models and outputs saved to `/workspace`
- **GPU Auto-Detection**: Optimizes for 4090/5090 vs cloud GPUs
- **Built-in Tools**:
  - ComfyUI (port 8188)
  - Jupyter Lab (port 8888)
  - FileBrowser (port 8080)
  - Zasper IDE (port 8048)
  - SSH Server (port 22)

## 📁 Directory Structure

**ComfyUI Installation** (read-only, in image):
```
/opt/comfyui-base/ComfyUI/   # Pre-installed ComfyUI with all dependencies
```

**Persistent Storage** (your data):
```
/workspace/
├── models/            # Your model files
├── output/            # Generated images
├── input/             # Input images
└── comfyui_args.txt   # Custom startup arguments
```

ComfyUI automatically uses `/workspace` for all user data through symlinks.

## ⚙️ Configuration

### Custom Arguments

Edit `/workspace/madapps/comfyui_args.txt`:
```
--highvram
--preview-method auto
--use-pytorch-cross-attention
```

### Environment Variables

- `PUBLIC_KEY`: SSH public key for authentication
- `RUNPOD_*`: Auto-detected RunPod environment

## 🔧 Development

### File Structure

```
.
├── Dockerfile.base       # Base image with CUDA and tools
├── Dockerfile.app        # ComfyUI application layer
├── docker-bake.hcl       # Build configuration
├── start-optimized.sh    # Startup script
├── BUILD.md             # Detailed build instructions
└── archive-reference/    # Old/reference files
```

### Build Flow

1. **First Time**: Build both base and app
2. **Update ComfyUI**: Only rebuild app layer
3. **Update CUDA/Python**: Rebuild base, then app

## 📊 Image Sizes

- Base image: ~2-3GB (CUDA, Python, tools)
- App layer: ~1-2GB (ComfyUI, PyTorch)
- Total: ~4-5GB (with layer sharing)
- Download on RunPod: Fast due to layer caching

## 🚀 Performance

- **First Pod Start**: ~30s (copies ComfyUI to workspace)
- **Subsequent Restarts**: Instant (uses persistent storage)
- **Model Loading**: From persistent `/workspace/models`
- **Output Saving**: To persistent `/workspace/output`

## 🛠️ Troubleshooting

### ComfyUI Not Starting?

Check logs:
```bash
docker logs <container-id>
```

### Models Not Found?

Place models in:
```
/workspace/madapps/models/checkpoints/
/workspace/madapps/models/loras/
/workspace/madapps/models/vae/
```

### GPU Not Detected?

The script auto-detects GPU type. Check:
```bash
nvidia-smi
```

## 📝 License

This project is licensed under the GPLv3 License.

## 🙏 Credits

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI) by comfyanonymous
- [ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager) by ltdrdata
- Built for [RunPod](https://runpod.io) infrastructure