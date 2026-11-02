#!/bin/bash
# Build the firmware from a Marlin checkout: ./scripts/build.sh path/to/Marlin
set -euo pipefail
dir="${1:?usage: build.sh path/to/Marlin}"
cd "$dir"
pio run -e mks_robin_nano_v1v2
bin=.pio/build/mks_robin_nano_v1v2/Robin_nano35.bin
sha256sum "$bin"
echo "Copy $dir/$bin to the SD card, then power on the printer."
