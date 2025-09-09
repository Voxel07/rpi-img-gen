#!/bin/bash

set -euo pipefail

BUILD_ID=${RANDOM}
RPI_BUILD_SVC="rpi_imagegen"
RPI_BUILD_USER="imagegen"
RPI_CUSTOMIZATIONS_DIR="voxel"
RPI_CONFIG="voxel"
RPI_OPTIONS="voxel"
RPI_IMAGE_NAME="voxel"

ensure_cleanup() {
  echo "Cleanup containers..."
  
  # Get container ID and clean up if it exists
  if RPI_BUILD_SVC_CONTAINER_ID=$(docker ps -aq --filter "name=${RPI_BUILD_SVC}-${BUILD_ID}" | head -n 1); then
    if [ -n "$RPI_BUILD_SVC_CONTAINER_ID" ]; then
      echo "Cleaning up container: $RPI_BUILD_SVC_CONTAINER_ID"
      docker kill "$RPI_BUILD_SVC_CONTAINER_ID" 2>/dev/null || true
      docker rm "$RPI_BUILD_SVC_CONTAINER_ID" 2>/dev/null || true
    else
      echo "No container found to cleanup"
    fi
  else
    echo "No container found to cleanup"
  fi
  
  echo "Cleanup complete."
}

# Set the trap to execute the ensure_cleanup function on EXIT
trap ensure_cleanup EXIT

# Create output directory if it doesn't exist
mkdir -p "${RPI_CUSTOMIZATIONS_DIR}/deploy"

echo "🔨 Building Docker image with rpi-image-gen to create ${RPI_BUILD_SVC}..."
docker compose build ${RPI_BUILD_SVC}

echo "🚀 Running image generation in container..."

# Remove any existing containers with the same name
docker rm -f ${RPI_BUILD_SVC}-${BUILD_ID} 2>/dev/null || true

# Run the build directly in one command
docker compose run --rm --name ${RPI_BUILD_SVC}-${BUILD_ID} ${RPI_BUILD_SVC} bash -c "
  # Setup binfmt_misc if needed
  if [ ! -f /proc/sys/fs/binfmt_misc/status ]; then
    echo 'Mounting binfmt_misc...'
    mkdir -p /proc/sys/fs/binfmt_misc
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || echo 'binfmt_misc mount failed, continuing...'
  fi
  
  # Register QEMU interpreters properly
  echo 'Setting up QEMU interpreters...'
  update-binfmts --enable qemu-aarch64 2>/dev/null || echo 'qemu-aarch64 setup failed, continuing...'
  update-binfmts --enable qemu-arm 2>/dev/null || echo 'qemu-arm setup failed, continuing...'
  
  cd /home/${RPI_BUILD_USER}/rpi-image-gen
  
  # Verify dependencies are properly installed
  echo '🔍 Checking dependencies...'
  ls -la /usr/bin/rsync /usr/bin/genimage /usr/bin/mtools || echo 'Some dependencies missing, but continuing...'
  
  echo '📦 Starting rpi-image-gen build...'
  echo 'Build command: sudo -E ./build.sh -D /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/ -c ${RPI_CONFIG} -o /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/${RPI_OPTIONS}.options'
  
  # Create output directory structure
  sudo mkdir -p /home/${RPI_BUILD_USER}/rpi-image-gen/work/${RPI_IMAGE_NAME}/deploy/
  
  sudo -E ./build.sh -D /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/ -c ${RPI_CONFIG} -o /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/${RPI_OPTIONS}.options || {
    echo '❌ Build failed, checking for partial results...'
    find /home/${RPI_BUILD_USER}/rpi-image-gen/work -name '*.img' 2>/dev/null || echo 'No .img files found'
    find /home/${RPI_BUILD_USER}/rpi-image-gen/work -type f -name '*' | head -20 || echo 'No files in work directory'
    exit 1
  }
  
  echo '✅ Build completed!'
  ls -la work/${RPI_IMAGE_NAME}/deploy/ || ls -la work/ || echo 'No output directory found'
" && echo "📋 Build container completed successfully"

# The container is removed automatically with --rm, but we still need to copy the file
# Let's run a temporary container to copy the file
echo "📋 Copying generated image..."
TEMP_CONTAINER=$(docker compose run -d ${RPI_BUILD_SVC} sleep 10)
sleep 2

# Generate timestamp for filename
TIMESTAMP=$(date +%m-%d-%Y-%H%M)
OUTPUT_FILE="${RPI_CUSTOMIZATIONS_DIR}/deploy/${RPI_IMAGE_NAME}-${TIMESTAMP}.img"

# Copy the file
docker cp "${TEMP_CONTAINER}:/home/${RPI_BUILD_USER}/rpi-image-gen/work/${RPI_IMAGE_NAME}/deploy/${RPI_IMAGE_NAME}.img" "./${OUTPUT_FILE}" || {
  echo "❌ Failed to copy image file. Let's check what's available:"
  docker exec ${TEMP_CONTAINER} find /home/${RPI_BUILD_USER}/rpi-image-gen/work -name "*.img" 2>/dev/null || echo "No .img files found"
  docker kill ${TEMP_CONTAINER} 2>/dev/null || true
  exit 1
}

# Clean up temp container
docker kill ${TEMP_CONTAINER} 2>/dev/null || true

echo "✅ Build completed successfully!"
echo "🚀 Output image: ${OUTPUT_FILE}"

# Verify the file exists and show its size
if [ -f "$OUTPUT_FILE" ]; then
  FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
  echo "📊 Image size: ${FILE_SIZE}"
else
  echo "❌ Error: Output file not found at ${OUTPUT_FILE}"
  exit 1
fi