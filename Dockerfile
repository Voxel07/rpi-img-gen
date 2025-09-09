FROM debian:bookworm AS base

# Install base dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
      build-essential \
      curl \
      git \
      ca-certificates \
      sudo \
      gpg \
      gpg-agent \
      binfmt-support \
      qemu-user-static \
  && rm -rf /var/lib/apt/lists/*

# Add Raspberry Pi GPG key
RUN curl -fsSL https://archive.raspberrypi.com/debian/raspberrypi.gpg.key \
  | gpg --dearmor > /usr/share/keyrings/raspberrypi-archive-keyring.gpg

# Clone rpi-image-gen at specific commit
ARG RPIIG_GIT_SHA=e5766aa9b2f5a6a09b241c5553833aaa3d4ac4c3
RUN git clone --no-checkout https://github.com/raspberrypi/rpi-image-gen.git && \
    cd rpi-image-gen && \
    git checkout ${RPIIG_GIT_SHA}

# Architecture-specific setup
ARG TARGETARCH
RUN echo "Building for architecture: ${TARGETARCH}"

RUN /bin/bash -c '\
  case "${TARGETARCH}" in \
    arm64) \
      echo "Building for arm64" && \
      apt-get update && \
      rpi-image-gen/install_deps.sh \
      ;; \
    amd64) \
      echo "Building for amd64 with cross-compilation support" && \
      \
      # Patch dependencies_check to bypass binfmt_misc requirement \
      if [ -f rpi-image-gen/scripts/dependencies_check ]; then \
        sed -i "s|\"\${binfmt_misc_required}\" == \"1\"|false|g" rpi-image-gen/scripts/dependencies_check; \
      else \
        echo "No dependencies_check file to patch"; \
      fi && \
      \
      # Install additional amd64 dependencies for cross-compilation \
      apt-get update && \
      apt-get install --no-install-recommends -y \
        dirmngr \
        slirp4netns \
        quilt \
        parted \
        debootstrap \
        zerofree \
        libcap2-bin \
        libarchive-tools \
        xxd \
        file \
        kmod \
        bc \
        pigz \
        arch-test \
        dosfstools \
        zip \
        unzip && \
      \
      # Run the patched install script \
      rpi-image-gen/install_deps.sh \
      ;; \
    *) \
      echo "Unsupported architecture: ${TARGETARCH}. Only arm64 and amd64 are supported." && \
      exit 1 \
      ;; \
  esac'

# Create non-root user
ENV USER=imagegen
RUN useradd -u 4000 -ms /bin/bash "$USER" && \
    echo "${USER}:${USER}" | chpasswd && \
    adduser ${USER} sudo && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to user and setup workspace
USER ${USER}
WORKDIR /home/${USER}

# Copy rpi-image-gen to user directory
RUN cp -r /rpi-image-gen ~/rpi-image-gen

# Initialize git submodules
WORKDIR /home/${USER}/rpi-image-gen
RUN git submodule update --init --recursive

WORKDIR /home/${USER}