# tinyos takeover

Builds an image that when booted will automatically flash the latest tinyos build onto a tinybox.

To build: `nix build .#nixosConfigurations.takeover.netboot`

It produces a result directory with `bzImage` and `initrd`

NOTE: it doesn't work on macOS, tested on Ubuntu 24.04