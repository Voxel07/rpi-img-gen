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

# Load binfmt_misc module and install dependencies
RUN /bin/bash -c '\
  # Try to load binfmt_misc module or create the mount point \
  if ! mount | grep -q binfmt_misc; then \
    mkdir -p /proc/sys/fs/binfmt_misc && \
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true; \
  fi && \
  \
  case "${TARGETARCH}" in \
    arm64) \
      echo "Building for arm64" && \
      apt-get update && \
      rpi-image-gen/install_deps.sh \
      ;; \
    amd64) \
      echo "Building for amd64 with cross-compilation support" && \
      \
      # Install all dependencies manually to avoid rpi-image-gen checks \
      apt-get update && \
      apt-get install --no-install-recommends -y \
        binfmt-support \
        qemu-user-static \
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
        bc \
        pigz \
        arch-test \
        dosfstools \
        zip \
        unzip \
        python3 \
        python3-debian \
        python3-distutils \
        fdisk \
        gpg \
        systemd-container && \
      \
      # Register qemu interpreters \
      update-binfmts --enable qemu-arm 2>/dev/null || true && \
      update-binfmts --enable qemu-aarch64 2>/dev/null || true && \
      \
      # Skip the original install_deps.sh to avoid binfmt_misc checks \
      echo "Dependencies installed manually, skipping rpi-image-gen/install_deps.sh" \
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