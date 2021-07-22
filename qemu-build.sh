#!/bin/bash
QEMU_VERSION="qemu-6.0.0"
QEMU_FILE="${QEMU_VERSION}.tar.xz"

# Install requirements
sudo apt-get install \
    libsdl2-dev \
    libpixman-1-dev \
    libgbm-dev \
    libepoxy-dev \
    libspice-server-dev \
    libspice-protocol-dev \
    libvirglrenderer-dev \
    libusbredirhost-dev \
    libusbredirparser-dev \
    libusb-1.0-0-dev \
    libcap-ng-dev \
    libseccomp-dev

# Download QEMU sources
wget "https://download.qemu.org/${QEMU_FILE}"
tar xvJf "${QEMU_FILE}"
rm "${QEMU_FILE}"
cd "${QEMU_VERSION}"

# Configure & build
./configure \
    --enable-membarrier \
    --enable-cap-ng \
    --enable-sdl \
    --enable-opengl \
    --enable-virglrenderer \
    --enable-system \
    --enable-modules \
    --audio-drv-list=pa \
    --target-list=x86_64-softmmu \
    --enable-kvm \
    --enable-spice \
    --enable-usb-redir \
    --enable-libusb \
    --enable-tools \
    --enable-seccomp \
    --enable-vhost-user

make -j$(nproc)
