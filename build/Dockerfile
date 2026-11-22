FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends make bc bison flex libssl-dev libelf-dev python3 cpio kmod rsync xz-utils git file ca-certificates perl gcc g++ libc6-dev dwarves && rm -rf /var/lib/apt/lists/*
