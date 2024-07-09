# tinyos takeover

Builds an image that when booted will automatically flash the latest tinyos build onto a tinybox.

## Usage

Install the dependencies:
```bash
sudo apt install -y parted build-essential
```

```bash
make
```

or

```bash
make iso
```

to build an iso that can be loaded over the BMC.
