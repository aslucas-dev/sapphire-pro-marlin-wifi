#!/bin/bash
# Send a G-code file to the printer's SD card: ./scripts/upload.sh IP file.gcode
# The printer must be idle, and nothing else may send commands to port 8080 meanwhile.
# Names are stored as 8.3: use up to 4 characters before the dot to keep the full name.
set -euo pipefail
ip="${1:?usage: upload.sh IP file.gcode}"
file="${2:?usage: upload.sh IP file.gcode}"
curl -sS --max-time 900 -H "Expect:" -H "Content-Type: application/octet-stream" \
  --data-binary "@$file" "http://$ip/upload?X-Filename=$(basename "$file")"
echo
