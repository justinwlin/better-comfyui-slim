# Build Instructions

## Using Depot (Recommended - Fastest)

Depot provides fast, cloud-based builds with automatic caching.

### First Time Build:
```bash
# Step 1: Build and push base image
depot bake -f docker-bake.hcl base-only --push

# Step 2: Build and push app image  
depot bake -f docker-bake.hcl app-only --push
```

### Build only the base image:
```bash
depot bake -f docker-bake.hcl base-only --push
```

### Build only the app image:
```bash
depot bake -f docker-bake.hcl app-only --push
```

## Using Docker Buildx (Local)

If you prefer local builds:

### Setup buildx (one time):
```bash
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap
```

### Build everything:
```bash
docker buildx bake -f docker-bake.hcl
```

### Build and push:
```bash
docker buildx bake -f docker-bake.hcl --push
```

## Build Strategy

The build is split into two parts for efficiency:

1. **Base Image** (`Dockerfile.base`):
   - Ubuntu 22.04
   - CUDA 12.4
   - Python 3.12
   - UV (deterministic package manager)
   - Jupyter, FileBrowser, Zasper
   - SSH server
   - Changes rarely, can be cached

2. **App Image** (`Dockerfile.app`):
   - ComfyUI
   - Custom nodes
   - PyTorch with CUDA support
   - Changes frequently

## Why UV Instead of Pip?

- **Deterministic**: Same dependencies every time
- **Faster**: 10-100x faster than pip
- **Reliable**: Better dependency resolution
- **Cached**: Smart caching of packages

## Environment Variables

Set these before building to customize:

```bash
export REGISTRY=yourregistry  # Default: justinrunpod
depot bake -f docker-bake.hcl --push
```

## Typical Workflow

1. First time - build both:
```bash
depot bake -f docker-bake.hcl --push
```

2. When updating ComfyUI only:
```bash
depot bake -f docker-bake.hcl app-only --push
```

3. When updating system packages:
```bash
depot bake -f docker-bake.hcl base-only --push
# Then rebuild app on new base
depot bake -f docker-bake.hcl app-only --push
```

## Image Sizes

- Base image: ~2-3GB (CUDA, Python, tools)
- App image: ~4-5GB (adds ComfyUI, PyTorch)
- Total: ~4-5GB (layers are shared)