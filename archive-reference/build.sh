#!/bin/bash
# Build script for ComfyUI Docker images

set -e

REGISTRY=${REGISTRY:-justinrunpod}
PLATFORM=${PLATFORM:-linux/amd64}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}ComfyUI Docker Build System${NC}"
echo "================================"

# Check if docker buildx is available
if ! docker buildx version &> /dev/null; then
    echo -e "${RED}Error: Docker buildx is required${NC}"
    echo "Please install Docker Desktop or enable buildx"
    exit 1
fi

# Parse command line arguments
BUILD_TYPE=${1:-all}
PUSH=${2:-false}

case $BUILD_TYPE in
    base)
        echo -e "${YELLOW}Building base image only...${NC}"
        docker buildx build \
            --platform $PLATFORM \
            -f Dockerfile.base \
            -t $REGISTRY/comfyui-base:latest \
            -t $REGISTRY/comfyui-base:cuda12.4-ubuntu22.04 \
            $([ "$PUSH" = "push" ] && echo "--push") \
            .
        ;;
    
    app)
        echo -e "${YELLOW}Building application image only...${NC}"
        docker buildx build \
            --platform $PLATFORM \
            -f Dockerfile.app \
            --build-arg BASE_IMAGE=$REGISTRY/comfyui-base:latest \
            -t $REGISTRY/comfyui:latest \
            $([ "$PUSH" = "push" ] && echo "--push") \
            .
        ;;
    
    all)
        echo -e "${YELLOW}Building all images...${NC}"
        
        # Build base first
        echo -e "${GREEN}Step 1/2: Building base image${NC}"
        docker buildx build \
            --platform $PLATFORM \
            -f Dockerfile.base \
            -t $REGISTRY/comfyui-base:latest \
            -t $REGISTRY/comfyui-base:cuda12.4-ubuntu22.04 \
            $([ "$PUSH" = "push" ] && echo "--push") \
            .
        
        # Then build app
        echo -e "${GREEN}Step 2/2: Building application image${NC}"
        docker buildx build \
            --platform $PLATFORM \
            -f Dockerfile.app \
            --build-arg BASE_IMAGE=$REGISTRY/comfyui-base:latest \
            -t $REGISTRY/comfyui:latest \
            $([ "$PUSH" = "push" ] && echo "--push") \
            .
        ;;
    
    bake)
        echo -e "${YELLOW}Using docker-bake.hcl...${NC}"
        docker buildx bake -f docker-bake.hcl $([ "$PUSH" = "push" ] && echo "--push")
        ;;
    
    *)
        echo "Usage: $0 [base|app|all|bake] [push]"
        echo ""
        echo "Options:"
        echo "  base  - Build only the base image with CUDA and tools"
        echo "  app   - Build only the ComfyUI application image"
        echo "  all   - Build both base and app images (default)"
        echo "  bake  - Use docker-bake.hcl for advanced build"
        echo ""
        echo "Add 'push' as second argument to push to registry"
        echo ""
        echo "Examples:"
        echo "  $0             # Build all images locally"
        echo "  $0 base push   # Build and push base image"
        echo "  $0 app         # Build app image only"
        exit 1
        ;;
esac

echo -e "${GREEN}Build complete!${NC}"

# Show image sizes
echo ""
echo "Image sizes:"
docker images | grep $REGISTRY/comfyui