{
  config,
  pkgs,
  modulesPath,
  inputs,
  ...
}:
let
  python3 = pkgs.python3.withPackages (
    ps: with ps; [
      tinyturing
      tinygrad
      numpy
      numba
      pillow
      pyserial
      psutil
    ]
  );
in
{
  imports = [
    "${modulesPath}/installer/netboot/netboot.nix"
  ];

  # *** netboot config

  system.build.netboot = pkgs.symlinkJoin {
    name = "netboot";
    paths = with config.system.build; [
      initialRamdisk
      kernel
    ];
    preferLocalBuild = true;
  };

  # *** initrd config

  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.emergencyAccess = true;

  boot.initrd.systemd.network.enable = true;
  boot.initrd.systemd.network.networks.ethernet-default-dhcp = {
    matchConfig = {
      Name = [
        "en*"
        "eth*"
      ];
    };
    networkConfig = {
      DHCP = "yes";
    };
  };

  # mount tmpfs at sysroot
  boot.initrd.systemd.mounts = [
    {
      where = "/";
      what = "tmpfs";
      type = "tmpfs";
      options = "mode=0755";
    }
  ];

  # stop at initrd
  boot.initrd.systemd.services.initrd-parse-etc.enable = false;
  boot.initrd.systemd.services.initrd-find-nixos-closure.enable = false;

  # *** kernel config

  boot.initrd.includeDefaultModules = true;
  boot.initrd.availableKernelModules = [
    "igb"
    "bnxt_en"
    "mlx5_core"
    "usbserial"
    "cdc_ether"
    "cdc_acm"
    "usb_storage"
    "uas"

    # ipmi
    "ipmi_msghandler"
    "ipmi_devintf"
    "ipmi_si"
    "acpi_ipmi"
    "ipmi_ssif"
  ];
  boot.blacklistedKernelModules = [
    "nouveau"
    "amdgpu"
  ];

  # *** system config

  boot.initrd.systemd.extraBin = {
    python3 = "${python3}/bin/python3";
    ip = "${pkgs.iproute2}/bin/ip";
    lsusb = "${pkgs.usbutils}/bin/lsusb";
    usbreset = "${pkgs.usb-reset}/bin/usb-reset";
    lspci = "${pkgs.pciutils}/bin/lspci";

    nc = "${pkgs.netcat-openbsd}/bin/nc";
    wget = "${pkgs.wget}/bin/wget";
    sgdisk = "${pkgs.gptfdisk}/bin/sgdisk";
    efibootmgr = "${pkgs.efibootmgr}/bin/efibootmgr";
    ipmitool = "${pkgs.ipmitool}/bin/ipmitool";
    grep = "${pkgs.gnugrep}/bin/grep";

    # busybox
    busybox = "${pkgs.busybox}/bin/busybox";
    pgrep = "${pkgs.busybox}/bin/busybox";
    watch = "${pkgs.busybox}/bin/busybox";
    awk = "${pkgs.busybox}/bin/busybox";
    pkill = "${pkgs.busybox}/bin/busybox";
    hostname = "${pkgs.busybox}/bin/busybox";
  };

  boot.initrd.systemd.storePaths = [
    pkgs.busybox
    pkgs.pciutils

    python3
    pkgs.python3

    inputs.tinyos
  ];

  boot.initrd.systemd.contents = {
    "/opt/tinybox/service/display/docs_qr.png".source = "${inputs.tinyos}/service/display/docs_qr.png";
    "/opt/tinybox/service/display/logo.png".source = "${inputs.tinyos}/service/display/logo.png";
    "/opt/tinybox/service/display/service.py".source = "${inputs.tinyos}/service/display/service.py";
    "/opt/tinybox/service/display/stats.py".source = "${inputs.tinyos}/service/display/stats.py";
  };

  boot.initrd.systemd.services.tinybox-display = {
    description = "tinybox-display";
    wantedBy = [ "initrd.target" ];
    unitConfig.DefaultDependencies = "no";
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 1;
      KillSignal = "SIGKILL";
      TimeoutStopSec = "1s";
    };
    script = ''
      python3 /opt/tinybox/service/display/service.py
    '';
  };

  boot.initrd.systemd.services.takeover = {
    description = "takeover";
    wantedBy = [ "initrd.target" ];
    after = [ "tinybox-display.service" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
    };
    script = ''
      set -x
      set +u

      source ${inputs.tinyos}/service/display/api.sh

      wait_for_display 5

      # wait for network to be up
      while ! ip addr show | grep -q "scope global"; do
        sleep 1
      done

      # find first /dev/sd{a-z} that is not mounted
      drive=""
      for i in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
        if ! mount | grep -q "/dev/sd$i" && [ -b "/dev/sd$i" ]; then
          drive="/dev/sd$i"
          break
        fi
      done

      if [ -z "$drive" ]; then
        # if no drive found, try /dev/nvme0n1
        if [ -b "/dev/nvme0n1" ]; then
          drive="/dev/nvme0n1"
        fi
      fi

      if [ -z "$drive" ]; then
        display_text "no drive found"
        exit 1
      fi

      display_text "using drive, $drive"
      sleep 1

      mkdir -p /tmp/tmp
      mount -t tmpfs -o size=96G tmpfs /tmp/tmp

      IMG_HOSTS="http://192.168.52.20:2543 http://192.168.52.16:2543"

      # determine which image we are downloading and flashing
      image_name="tinyos.core.img"
      # see if any pci devices have NVIDIA
      if lspci | grep -q "NVIDIA"; then
        image_name="tinyos.green.img"
      elif lspci | grep -q "Radeon"; then
        image_name="tinyos.red.img"
      fi
      display_text "downloading,$image_name"
      sleep 1

      # download the os image
      # first find a host that is accessible and that has both images
      selected_host=""
      for host in $IMG_HOSTS; do
        if wget -q --spider "$host/$image_name"; then
          selected_host="$host"
          break
        fi
      done

      if [ -z "$selected_host" ]; then
        display_text "no download host found"
        exit 1
      else
        display_text "using host,$selected_host"
      fi

      wget -b -o /tmp/log -O /tmp/tmp/tinyos.img "$selected_host/$image_name"

      # wait until the image is downloaded
      while true; do
        sleep 1

        # extract the downloaded percentage from the log file
        percentage=$(grep -oP '\d+%' /tmp/log | tail -n1)
        # extract the estimated time left from the log file
        time_left=$(grep -oP '(\d+m)?\d+s' /tmp/log | tail -n1)

        display_text "downloading,$image_name,$percentage - $time_left"

        if ! pgrep -f "wget -b -o /tmp/log -O /tmp/tmp/tinyos.img" > /dev/null; then
          break
        fi
      done

      # see if the image was downloaded successfully by seeing if there is a 100% in the log file
      if ! grep -q "100%" /tmp/log; then
        display_text "download failed"
        exit 1
      fi

      display_text "flashing,$image_name,$drive"
      sleep 1

      file_size=$(stat -c %s /tmp/tmp/tinyos.img)
      watch -t -n1 pkill -USR1 dd > /dev/null &

      # write the image to the drive
      dd if=/tmp/tmp/tinyos.img of="$drive" bs=16M oflag=direct 2>&1 | while read -r line; do
        case $line in
          *"bytes"*)
            # extract the written bytes from the line
            written=$(echo "$line" | grep -oP '\d+' | head -n1)
            # calculate the percentage of the written bytes
            percentage=$(awk "BEGIN {print int(($written/$file_size)*100)}")
            # extract the speed
            speed=$(echo "$line" | grep -oP '(\d+.\d+MB/s)|(\d+ MB/s)|(\d+B/s)' || echo "0 MB/s")
            display_text "flashing,$image_name,$drive,$percentage% - $speed"
            ;;
        esac
      done
      pkill watch || true

      display_text "flashed,$image_name,$drive"

      # fix the backup gpt header
      sgdisk -e "$drive"

      # delete previous tinyos uefi boot entries no bash
      entries="$(efibootmgr | grep -i "tinyos" | grep -oP 'Boot\d+' | grep -oP '\d+')"
      for entry in $entries; do
        efibootmgr -b "$entry" -B
      done

      # tell uefi to boot from the internal drive
      efibootmgr --create --disk "$drive" --part 1 --label "tinyos" --loader '\EFI\BOOT\BOOTX64.EFI'
      bootnum="$(efibootmgr | grep -i "tinyos" | grep -oP 'Boot\d+' | grep -oP '\d+' | head -n1)"
      efibootmgr -n "$bootnum"

      display_text "Rebooting,$bootnum"
      display_text "Rebooting..."
      sleep 1

      systemctl kill tinybox-display
      reboot
    '';
  };

  networking.hostName = "takeover";

  # stateless so just set to latest
  system.stateVersion = config.system.nixos.release;
}
