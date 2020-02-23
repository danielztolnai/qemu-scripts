#!/bin/bash
QEMU_VERSION="qemu-4.2.0"
QEMU_FILE="${QEMU_VERSION}.tar.xz"

# Install requirements
LIBPULSE_DEB="libpulse-dev_11.1-1ubuntu7.5_amd64.deb"
wget "http://archive.ubuntu.com/ubuntu/ubuntu/pool/main/p/pulseaudio/${LIBPULSE_DEB}"
sudo dpkg -i "${LIBPULSE_DEB}"
rm "${LIBPULSE_DEB}"

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
    libusb-1.0-0-dev

# Download QEMU sources
wget "https://download.qemu.org/${QEMU_FILE}"
tar xvJf "${QEMU_FILE}"
rm "${QEMU_FILE}"
cd "${QEMU_VERSION}"

# Configure & build
./configure \
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
    --enable-libusb

make -j$(nproc)
