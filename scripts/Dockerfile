ARG BASE_IMAGE=ubuntu:24.04
FROM $BASE_IMAGE

# arm64 or amd64: the CPU type of the image to build (scripts/local-build-in-docker.sh sets it)
ARG ARCH

# the same package list as the release workflow
COPY scripts/install-build-deps.sh /usr/local/bin/install-build-deps.sh

# hadolint ignore=DL3008,DL3009
RUN install-build-deps.sh "$ARCH" \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Ensure privileged operations work inside the container
VOLUME ["/sys/fs/cgroup"]
