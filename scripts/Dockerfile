ARG BASE_IMAGE=ubuntu:24.04
FROM $BASE_IMAGE

ARG GRUB_EFI_PKG

RUN set -e; \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update -qq; \
  apt-get install -y -qq \
  debootstrap parted e2fsprogs dosfstools \
  dialog $GRUB_EFI_PKG qemu-utils \
  qemu-user-static gzip \
  sudo udev kpartx psmisc jq; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/*

# Ensure privileged operations work inside the container
VOLUME ["/sys/fs/cgroup"]