all: build

clean:
	rm -f localhost.apkovl.tar localhost.apkovl.tar.gz
	rm -f takeover.img.part takeover.img
	rm -f takeover.iso
	rm -f boot/modloop-lts
	sudo umount tmp || true
	rmdir tmp || true

download-boot:
	curl -o boot/modloop-lts https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/netboot-3.19.1/modloop-lts

build-apkovl:
	# update opt/tinybox/takeover.sh inside of the tarball
	cp apkovl/localhost.apkovl.tar.gz ./localhost.apkovl.tar.gz
	gzip -d localhost.apkovl.tar.gz
	pushd apkovl && tar -uf ../localhost.apkovl.tar etc/network/interfaces --owner=0 --group=0
	pushd apkovl && tar -uf ../localhost.apkovl.tar opt/tinybox/takeover.sh --owner=0 --group=0
	# generate a new apkovl
	gzip localhost.apkovl.tar

build: download-boot build-apkovl
	bash ./img.sh

	# mount the image
	mkdir -p tmp
	sudo mount -o loop,offset=1048576 takeover.img tmp

	# copy over everything
	sudo cp ./.alpine-release tmp/
	sudo cp localhost.apkovl.tar.gz tmp/
	sudo cp -r ./apks tmp/
	sudo cp -r ./boot tmp/
	sudo cp -r ./cache tmp/
	sudo cp -r ./efi tmp/

	sudo umount tmp

iso:
	mkdir -p tmp
	sudo mount -o loop,offset=1048576 takeover.img tmp

	xorriso -as mkisofs -o takeover.iso -r -V "takeover" \
		-J -joliet-long \
		-b boot/syslinux/isolinux.bin \
		-c boot/syslinux/boot.cat \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		-eltorito-alt-boot \
		-e boot/grub/efi.img \
		-no-emul-boot \
		-isohybrid-gpt-basdat \
		tmp

	sudo umount tmp

.PHONY: clean build-apkovl build
