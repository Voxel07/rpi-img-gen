#!/bin/bash

set -euo pipefail

BUILD_ID=${RANDOM}
RPI_BUILD_SVC="rpi_imagegen"
RPI_BUILD_USER="imagegen"
RPI_CUSTOMIZATIONS_DIR="macmind"
RPI_CONFIG="macmind"
RPI_OPTIONS="macmind"
RPI_IMAGE_NAME="macmind"

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

# Start the container in detached mode
docker compose run --name ${RPI_BUILD_SVC}-${BUILD_ID} -d ${RPI_BUILD_SVC} sleep infinity

# Wait for container to be ready
sleep 2

# Execute the build command
echo "📦 Executing rpi-image-gen build..."
docker compose exec ${RPI_BUILD_SVC} bash -c "\
  cd /home/${RPI_BUILD_USER}/rpi-image-gen && \
  sudo ./build.sh -D /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/ -c ${RPI_CONFIG} -o /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/${RPI_OPTIONS}.options"

# Get container ID for file copying
CID=$(docker ps -aq --filter "name=${RPI_BUILD_SVC}-${BUILD_ID}" | head -n 1)

if [ -z "$CID" ]; then
  echo "❌ Error: Container not found"
  exit 1
fi

# Generate timestamp for filename
TIMESTAMP=$(date +%m-%d-%Y-%H%M)
OUTPUT_FILE="${RPI_CUSTOMIZATIONS_DIR}/deploy/${RPI_IMAGE_NAME}-${TIMESTAMP}.img"

echo "📋 Copying generated image from container..."
docker cp "${CID}:/home/${RPI_BUILD_USER}/rpi-image-gen/work/${RPI_IMAGE_NAME}/deploy/${RPI_IMAGE_NAME}.img" "./${OUTPUT_FILE}"

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