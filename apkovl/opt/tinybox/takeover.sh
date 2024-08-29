#!/bin/sh
set -x

sleep 1

# list of hosts to check for updates
UPDATE_URLS="http://192.168.52.20:2543/takeover.sh http://192.168.52.16:2543/takeover.sh https://raw.githubusercontent.com/tinygrad/tinyos-takeover/main/apkovl/opt/tinybox/takeover.sh"
# list of hosts to fetch the image from
IMG_HOSTS="http://192.168.52.20:2543 http://192.168.52.16:2543"

# Check if the script is up to date
success=0
for url in $UPDATE_URLS; do
  if wget -q -O /tmp/update.sh "$url"; then
    success=1
    break
  fi
done

if [ "$success" -eq 0 ]; then
  echo "text,Failed Update" | nc -U /run/tinybox-screen.sock
  exit 1
fi

remote_script_hash="$(sha256sum /tmp/update.sh | awk '{print $1}')"
local_script_hash="$(sha256sum /opt/tinybox/takeover.sh | awk '{print $1}')"
if [ "$remote_script_hash" != "$local_script_hash" ]; then
  echo "text,Updating..." | nc -U /run/tinybox-screen.sock
  sleep 1
  mv /tmp/update.sh /opt/tinybox/takeover.sh
  chmod +x /opt/tinybox/takeover.sh
  exec /opt/tinybox/takeover.sh "$@"
  exit 0
fi

# system check
EXPECTED_GPU_COUNT=6
EXPECTED_GPU_LINK_SPEED="16GT/s"
EXPECTED_GPU_LINK_WIDTH="x16"
EXPECTED_MEMORY_SIZE_GB=128
EXPECTED_CORE_COUNT=32
EXPECTED_DRIVE_COUNT=4
EXPECTED_DRIVE_LINK_SPEED="16GT/s"
EXPECTED_DRIVE_LINK_WIDTH="x4"

echo "atext,System Check.. ,System Check ..,System Check. ." | nc -U /run/tinybox-screen.sock
system_info="$(lshw -json)"

# first check the gpus
gpu_busids="$(echo "$system_info" | jq -r '.. | objects | select(.class == "display") | select(.vendor | . and contains("ASPEED") | not) | .businfo | .[4:]')"
gpu_count=$(echo "$gpu_busids" | wc -l)
echo "text,Found $gpu_count GPUs" | nc -U /run/tinybox-screen.sock
if [ "$gpu_count" -ne "$EXPECTED_GPU_COUNT" ]; then
  echo "text,GPU Count should be ${EXPECTED_GPU_COUNT},is $gpu_count" | nc -U /run/tinybox-screen.sock
  exit 1
fi
i=0
for busid in $gpu_busids; do
  echo "text,Checking GPU $i,$busid" | nc -U /run/tinybox-screen.sock

  link_speed=$(lspci -vv -s "$busid" | grep "LnkCap:" | grep -oP 'Speed \d+GT/s' | grep -oP '\d+GT/s')
  if [ "$link_speed" != "$EXPECTED_GPU_LINK_SPEED" ]; then
    echo "text,$busid - GPU $i,not at $EXPECTED_GPU_LINK_SPEED,at $link_speed" | nc -U /run/tinybox-screen.sock
    exit 1
  fi
  link_width=$(lspci -vv -s "$busid" | grep "LnkCap:" | grep -oP 'Width x\d+' | grep -oP 'x\d+')
  if [ "$link_width" != "$EXPECTED_GPU_LINK_WIDTH" ]; then
    echo "text,$busid - GPU $i,not at $EXPECTED_GPU_LINK_WIDTH,at $link_width" | nc -U /run/tinybox-screen.sock
    exit 1
  fi

  # ensure resizable bar is enabled
  if ! lspci -vv -s "$busid" | grep -q "Resizable BAR"; then
    echo "text,$busid - GPU $i,Resizable BAR not enabled" | nc -U /run/tinybox-screen.sock
    exit 1
  fi

  i=$((i + 1))
done

# check the ram
memory_size=$(echo "$system_info" | jq -r '.. | objects | select(.id == "memory") | .size')
memory_size_gb=$(echo "$memory_size" | awk '{print int($1/1024/1024/1024)}')
echo "text,Found $memory_size_gb GB" | nc -U /run/tinybox-screen.sock
if [ "$memory_size_gb" -ne "$EXPECTED_MEMORY_SIZE_GB" ]; then
  echo "text,Memory should be ${EXPECTED_MEMORY_SIZE_GB} GB,is $memory_size_gb GB" | nc -U /run/tinybox-screen.sock
  exit 1
fi

# check the cpu
core_count=$(echo "$system_info" | jq -r '.. | objects | select(.class == "processor") | .configuration.enabledcores')
echo "text,Found $core_count Cores" | nc -U /run/tinybox-screen.sock
if [ "$core_count" -ne "$EXPECTED_CORE_COUNT" ]; then
  echo "text,Core Count should be ${EXPECTED_CORE_COUNT},is $core_count" | nc -U /run/tinybox-screen.sock
  exit 1
fi

# check the nvme drives
drive_busids=$(echo "$system_info" | jq -r '.. | objects | select(.class == "disk") | select(.description | . and contains("NVMe")) | select(.businfo | . and contains("nvme")) | .businfo')
drive_count=$(echo "$drive_busids" | wc -l)
echo "text,Found $drive_count Drives" | nc -U /run/tinybox-screen.sock
if [ "$drive_count" -ne "$EXPECTED_DRIVE_COUNT" ]; then
  echo "text,Drive Count should be ${EXPECTED_DRIVE_COUNT},is $drive_count" | nc -U /run/tinybox-screen.sock
  exit 1
fi
i=0
for busid in $drive_busids; do
  # grab the pcie busid
  nvmeid="$(echo "$busid" | grep -oP '@\d' | grep -oP '\d')"
  busid="$(cat /sys/class/nvme/nvme"$nvmeid"/address)"
  echo "text,Checking Drive $i,$busid" | nc -U /run/tinybox-screen.sock

  link_speed=$(lspci -vv -s "$busid" | grep "LnkCap:" | grep -oP 'Speed \d+GT/s' | grep -oP '\d+GT/s')
  if [ "$link_speed" != "$EXPECTED_DRIVE_LINK_SPEED" ]; then
    echo "text,$busid - Drive $i,not at $EXPECTED_DRIVE_LINK_SPEED,at $link_speed" | nc -U /run/tinybox-screen.sock
    exit 1
  fi
  link_width=$(lspci -vv -s "$busid" | grep "LnkCap:" | grep -oP 'Width x\d+' | grep -oP 'x\d+')
  if [ "$link_width" != "$EXPECTED_DRIVE_LINK_WIDTH" ]; then
    echo "text,$busid - Drive $i,not at $EXPECTED_DRIVE_LINK_WIDTH,at $link_width" | nc -U /run/tinybox-screen.sock
    exit 1
  fi

  i=$((i + 1))
done

echo "text,System Check Complete" | nc -U /run/tinybox-screen.sock
sleep 1

# find first /dev/sd{a-z} that is not mounted
drive=""
for i in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
  if ! mount | grep -q "/dev/sd$i"; then
    drive="/dev/sd$i"
    break
  fi
done

if [ -z "$drive" ]; then
  echo "text,No Drive Found" | nc -U /run/tinybox-screen.sock
  exit 1
fi

echo "text,Using Drive,$drive" | nc -U /run/tinybox-screen.sock
sleep 1

# make a tmpfs to store the image
mkdir -p /tmp/tmp
mount -t tmpfs -o size=96G tmpfs /tmp/tmp

# determine which image we are downloading and flashing
is_nvidia=$(echo "$system_info" | jq -r '.. | objects | select(.class == "display") | select(.vendor | . and contains("ASPEED") | not) | .vendor' | head -n1 | grep -i "nvidia")
if [ -n "$is_nvidia" ]; then
  echo "text,Downloading green Image" | nc -U /run/tinybox-screen.sock
else
  echo "text,Downloading red Image" | nc -U /run/tinybox-screen.sock
fi
sleep 1

# download the os image
# first find a host that is accessible and that has both images
selected_host=""
for host in $IMG_HOSTS; do
  if wget -q --spider "$host/tinyos.green.img" && wget -q --spider "$host/tinyos.red.img"; then
    selected_host="$host"
    break
  fi
done

if [ -z "$selected_host" ]; then
  echo "text,No Host Found" | nc -U /run/tinybox-screen.sock
  exit 1
else
  echo "text,Using Host,$selected_host" | nc -U /run/tinybox-screen.sock
fi

if [ -n "$is_nvidia" ]; then
  wget -b -o /tmp/log -O /tmp/tmp/tinyos.img "$selected_host/tinyos.green.img"
else
  wget -b -o /tmp/log -O /tmp/tmp/tinyos.img "$selected_host/tinyos.red.img"
fi

# wait until the image is downloaded
while true; do
  sleep 1

  # extract the downloaded percentage from the log file
  percentage=$(grep -oP '\d+%' /tmp/log | tail -n1)
  # extract the estimated time left from the log file
  time_left=$(grep -oP '(\d+m)?\d+s' /tmp/log | tail -n1)

  echo "text,Downloading Image,$percentage - $time_left" | nc -U /run/tinybox-screen.sock

  if ! pgrep -f "wget -b -o /tmp/log -O /tmp/tmp/tinyos.img" > /dev/null; then
    break
  fi
done

# see if the image was downloaded successfully by seeing if there is a 100% in the log file
if ! grep -q "100%" /tmp/log; then
  echo "text,Download Failed" | nc -U /run/tinybox-screen.sock
  exit 1
fi

echo "text,Flashing Image" | nc -U /run/tinybox-screen.sock

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
      speed=$(echo "$line" | grep -oP '(\d+.\d+MB/s)|(\d+ MB/s)|(\d+B/s)')
      echo "text,Flashing Image,$percentage% - $speed" | nc -U /run/tinybox-screen.sock
      ;;
  esac
done
pkill watch

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

echo "text,Flashing Complete,Rebooting" | nc -U /run/tinybox-screen.sock
sleep 1
reboot
