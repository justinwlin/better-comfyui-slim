# docker-bake.hcl - BuildKit bake configuration
# Usage with depot: depot bake -f docker-bake.hcl --push
# Usage with docker: docker buildx bake -f docker-bake.hcl

variable "REGISTRY" {
  default = "justinrunpod"
}

variable "UBUNTU_VERSION" {
  default = "22.04"
}

variable "CUDA_VERSION" {
  default = "12.4"
}

variable "PYTHON_VERSION" {
  default = "3.12"
}

variable "PYTORCH_VERSION" {
  default = "2.5.1"
}

variable "BASE_TAG" {
  default = "ubuntu22.04-cuda12.4-python3.12"
}

variable "APP_TAG" {
  default = "ubuntu22.04-cuda12.4-python3.12-pytorch2.5.1"
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
    "${REGISTRY}/ubuntu-cuda-python:${BASE_TAG}",
    "${REGISTRY}/ubuntu-cuda-python:latest",
    "${REGISTRY}/ubuntu-cuda-python:ubuntu${UBUNTU_VERSION}-cuda${CUDA_VERSION}-python${PYTHON_VERSION}"
  ]
  platforms = ["linux/amd64"]
  cache-from = ["type=registry,ref=${REGISTRY}/ubuntu-cuda-python:buildcache"]
  cache-to = ["type=registry,ref=${REGISTRY}/ubuntu-cuda-python:buildcache,mode=max"]
  output = ["type=registry"]
}

# ComfyUI application image
target "comfyui" {
  context = "."
  dockerfile = "Dockerfile.app"
  tags = [
    "${REGISTRY}/ubuntu-cuda-comfyui:${APP_TAG}",
    "${REGISTRY}/ubuntu-cuda-comfyui:latest",
    "${REGISTRY}/ubuntu-cuda-comfyui:comfyui-pytorch${PYTORCH_VERSION}",
    # Keep simple alias for backward compatibility
    "${REGISTRY}/comfyui:latest"
  ]
  platforms = ["linux/amd64"]
  cache-from = ["type=registry,ref=${REGISTRY}/ubuntu-cuda-comfyui:buildcache"]
  cache-to = ["type=registry,ref=${REGISTRY}/ubuntu-cuda-comfyui:buildcache,mode=max"]
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