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

the takeover image will fetch for an image from a http server, and flash it to the tinybox after doing some checks.
