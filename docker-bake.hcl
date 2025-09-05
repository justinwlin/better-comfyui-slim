# docker-bake.hcl - BuildKit bake configuration
# Usage with depot: depot bake -f docker-bake.hcl --push
# Usage with docker: docker buildx bake -f docker-bake.hcl

variable "REGISTRY" {
  default = "justinrunpod"
}

variable "BASE_TAG" {
  default = "cuda12.4-ubuntu22.04-python3.12"
}

group "default" {
  targets = ["base", "comfyui"]
}

# Build just the base
group "base-only" {
  targets = ["base"]
}

# Build just the app
group "app-only" {
  targets = ["comfyui"]
}

# Base image with CUDA, Python, and tools
target "base" {
  context = "."
  dockerfile = "Dockerfile.base"
  tags = [
    "${REGISTRY}/ubuntu-cuda12.4-python3.12-uv:${BASE_TAG}",
    "${REGISTRY}/ubuntu-cuda12.4-python3.12-uv:latest"
  ]
  platforms = ["linux/amd64"]
  cache-from = ["type=registry,ref=${REGISTRY}/ubuntu-cuda12.4-python3.12-uv:buildcache"]
  cache-to = ["type=registry,ref=${REGISTRY}/ubuntu-cuda12.4-python3.12-uv:buildcache,mode=max"]
  output = ["type=registry"]
}

# ComfyUI application image
target "comfyui" {
  context = "."
  dockerfile = "Dockerfile.app"
  tags = [
    "${REGISTRY}/comfyui:latest",
    "${REGISTRY}/comfyui:${BASE_TAG}"
  ]
  platforms = ["linux/amd64"]
  cache-from = ["type=registry,ref=${REGISTRY}/comfyui:buildcache"]
  cache-to = ["type=registry,ref=${REGISTRY}/comfyui:buildcache,mode=max"]
  output = ["type=registry"]
  # Use the base target directly as build context
  contexts = {
    base-image = "target:base"
  }
}

# Development target (includes extra tools)
target "dev" {
  inherits = ["comfyui"]
  tags = ["${REGISTRY}/comfyui:dev"]
  args = {
    DEV_MODE = "true"
  }
}

# Minimal target (smallest possible image)
target "minimal" {
  context = "."
  dockerfile = "Dockerfile.minimal"
  tags = ["${REGISTRY}/comfyui:minimal"]
  platforms = ["linux/amd64"]
}