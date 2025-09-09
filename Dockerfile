#!/bin/bash

set -euo pipefail

RPI_BUILD_USER="imagegen"
RPI_CUSTOMIZATIONS_DIR="voxel"
RPI_CONFIG="voxel"
RPI_OPTIONS="voxel"
RPI_IMAGE_NAME="voxel"
IMAGE_TAG="rpi-imagegen:latest"

# Create output directory if it doesn't exist
mkdir -p "${RPI_CUSTOMIZATIONS_DIR}/deploy"

echo "🔨 Building Docker image directly..."
docker build \
  --build-arg TARGETARCH=amd64 \
  --build-arg RPIIG_GIT_SHA=e5766aa9b2f5a6a09b241c5553833aaa3d4ac4c3 \
  -t ${IMAGE_TAG} \
  .

echo "🚀 Running image generation in container..."

# Run the container with all necessary privileges and mounts
docker run \
  --rm \
  --privileged \
  -v "$(pwd)/${RPI_CUSTOMIZATIONS_DIR}:/home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}" \
  -v /dev:/dev \
  --cap-add=SYS_ADMIN \
  --cap-add=MKNOD \
  --cap-add=SYS_MODULE \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  -e DEBIAN_FRONTEND=noninteractive \
  ${IMAGE_TAG} \
  bash -c "
    set -e
    
    echo '🔧 Setting up container environment...'
    
    # Setup binfmt_misc
    if [ ! -f /proc/sys/fs/binfmt_misc/status ]; then
      echo 'Mounting binfmt_misc...'
      mkdir -p /proc/sys/fs/binfmt_misc
      mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || echo 'binfmt_misc mount failed, continuing...'
    fi
    
    # Register QEMU interpreters
    echo 'Setting up QEMU interpreters...'
    update-binfmts --enable qemu-aarch64 2>/dev/null || echo 'qemu-aarch64 setup failed'
    update-binfmts --enable qemu-arm 2>/dev/null || echo 'qemu-arm setup failed'
    
    # Verify key dependencies
    echo '🔍 Verifying dependencies...'
    which rsync genimage mtools python3 || echo 'Some tools missing'
    
    cd /home/${RPI_BUILD_USER}/rpi-image-gen
    
    # Show available configurations
    echo '📋 Available configurations:'
    ls -la /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/ || echo 'No customization directory found'
    
    # Create output directory structure
    echo '📁 Creating output directories...'
    mkdir -p work/${RPI_IMAGE_NAME}/deploy/
    
    echo '📦 Starting rpi-image-gen build...'
    echo 'Command: ./build.sh -D /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/ -c ${RPI_CONFIG} -o /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/${RPI_OPTIONS}.options'
    
    # Run the build
    ./build.sh \
      -D /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/ \
      -c ${RPI_CONFIG} \
      -o /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/${RPI_OPTIONS}.options || {
      
      echo '❌ Build failed. Diagnostic information:'
      echo '--- Checking work directory ---'
      find work -type f -name '*.img' 2>/dev/null || echo 'No .img files found'
      find work -type f | head -10 || echo 'No files in work directory'
      
      echo '--- Checking logs ---'
      find work -name '*.log' -exec tail -20 {} + 2>/dev/null || echo 'No log files found'
      
      exit 1
    }
    
    echo '✅ Build completed successfully!'
    
    # List generated files
    echo '📁 Generated files:'
    find work -name '*.img' -exec ls -lh {} + || echo 'No .img files found'
    
    # Copy to mounted volume (this should be automatically available)
    if [ -f work/${RPI_IMAGE_NAME}/deploy/${RPI_IMAGE_NAME}.img ]; then
      cp work/${RPI_IMAGE_NAME}/deploy/${RPI_IMAGE_NAME}.img /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/deploy/
      echo '📋 Image copied to output directory'
    else
      echo '⚠️ Expected image file not found, checking alternatives...'
      find work -name '*.img' -exec cp {} /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/deploy/ \;
    fi
"

# Generate timestamp for filename
TIMESTAMP=$(date +%m-%d-%Y-%H%M)

# Find the generated image file
if ls "${RPI_CUSTOMIZATIONS_DIR}/deploy"/*.img 1> /dev/null 2>&1; then
  # Rename to include timestamp
  for img_file in "${RPI_CUSTOMIZATIONS_DIR}/deploy"/*.img; do
    if [ -f "$img_file" ]; then
      new_name="${RPI_CUSTOMIZATIONS_DIR}/deploy/${RPI_IMAGE_NAME}-${TIMESTAMP}.img"
      mv "$img_file" "$new_name"
      echo "✅ Build completed successfully!"
      echo "🚀 Output image: ${new_name}"
      
      FILE_SIZE=$(du -h "$new_name" | cut -f1)
      echo "📊 Image size: ${FILE_SIZE}"
      break
    fi
  done
else
  echo "❌ No image files found in output directory"
  echo "📁 Contents of ${RPI_CUSTOMIZATIONS_DIR}/deploy/:"
  ls -la "${RPI_CUSTOMIZATIONS_DIR}/deploy/" || echo "Directory doesn't exist"
  exit 1
fi