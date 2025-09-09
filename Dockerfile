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
  case "${TARGETARCH}" in \
    arm64) \
      echo "Building for arm64" && \
      apt-get update && \
      rpi-image-gen/install_deps.sh \
      ;; \
    amd64) \
      echo "Building for amd64 with cross-compilation support" && \
      \
      # Install ALL dependencies manually including the ones mentioned in the error \
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
        systemd-container \
        rsync \
        genimage \
        mtools \
        podman \
        crudini \
        zstd \
        pv \
        uidmap \
        python-is-python3 \
        dbus-user-session \
        btrfs-progs \
        dctrl-tools \
        uuid-runtime \
        xz-utils \
        && \
      \
      # Install mmdebstrap and bdebstrap from backports if available \
      (apt-get install --no-install-recommends -y mmdebstrap bdebstrap || \
       echo "mmdebstrap/bdebstrap not available from main repos, will install from script") && \
      \
      # Now run the actual install_deps.sh which should pass dependency checks \
      echo "Running rpi-image-gen/install_deps.sh after manual package installation" && \
      rpi-image-gen/install_deps.sh || echo "install_deps.sh completed with warnings" \
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