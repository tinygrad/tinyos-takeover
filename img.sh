#!/usr/bin/env bash

# align partition size
size=$((700 * (1 << 20)))
alignment=$((1024 * (1 << 10)))
size=$(((size + alignment - 1) / alignment * alignment))
echo "size: $size"

# make partition
mkfs.fat -F 32 -n takeover -C takeover.img.part $((size >> 10))

# put partition into disk image
dd if=takeover.img.part of=takeover.img conv=sparse obs=512 seek=$((alignment / 512))
truncate -s "+$alignment" takeover.img

# align disk image and partition
parted --align optimal -s takeover.img mklabel gpt
parted --align optimal -s takeover.img mkpart ESP "${alignment}B" 100%
parted --align optimal -s takeover.img set 1 boot on
