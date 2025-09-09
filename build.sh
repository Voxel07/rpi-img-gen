#!/bin/bash

set -eu

BUILD_ID=${RANDOM}
RPI_BUILD_SVC="rpi_imagegen"
RPI_BUILD_USER="imagegen"
RPI_CUSTOMIZATIONS_DIR="macmind"
RPI_CONFIG="macmind"
RPI_OPTIONS="macmind"
RPI_IMAGE_NAME="macmind"

ensure_cleanup() {
  echo "Cleanup containers..."

  RPI_BUILD_SVC_CONTAINER_ID=$(docker ps -a --filter "name=${RPI_BUILD_SVC}-${BUILD_ID}" --format "{{.ID}}" | head -n 1) \
    && docker kill ${RPI_BUILD_SVC_CONTAINER_ID} \
    && docker rm ${RPI_BUILD_SVC_CONTAINER_ID}

  echo "Cleanup complete."
}

# Set the trap to execute the ensure_cleanup function on EXIT
trap ensure_cleanup EXIT

# Build a customer raspberry pi image
# with the wifi setup service included
#
echo "🔨 Building Docker image with rpi-image-gen to create ${RPI_BUILD_SVC}..."
docker compose build ${RPI_BUILD_SVC}

echo "🚀 Running image generation in container..."
docker compose run --name ${RPI_BUILD_SVC}-${BUILD_ID} -d ${RPI_BUILD_SVC} \
  && docker compose exec ${RPI_BUILD_SVC} bash -c "/home/${RPI_BUILD_USER}/rpi-image-gen/build.sh -D /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/ -c ${RPI_CONFIG} -o /home/${RPI_BUILD_USER}/${RPI_CUSTOMIZATIONS_DIR}/${RPI_OPTIONS}.options" \
  && CID=$(docker ps -a --filter "name=${RPI_BUILD_SVC}-${BUILD_ID}" --format "{{.ID}}" | head -n 1) \
  && docker cp ${CID}:/home/${RPI_BUILD_USER}/rpi-image-gen/work/${RPI_IMAGE_NAME}/deploy/${RPI_IMAGE_NAME}.img ./${RPI_CUSTOMIZATIONS_DIR}/deploy/${RPI_IMAGE_NAME}-$(date +%m-%d-%Y-%H%M).img \

echo "🚀 Completed -> ${RPI_CUSTOMIZATIONS_DIR}/deploy/${RPI_IMAGE_NAME}-$(date +%m-%d-%Y-%H%M).img"
