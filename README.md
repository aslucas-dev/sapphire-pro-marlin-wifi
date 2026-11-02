# Sapphire Pro: MKS WiFi on Marlin 2.1.x

Getting the MKS WiFi module (ESP-12S) working on a Two Trees Sapphire Pro with a
Robin Nano V1.2 board, running Marlin `bugfix-2.1.x` with the Color UI. G-code
files can now be sent over WiFi and printed from the SD card.

This repository documents the diagnosis, the fixes and the test results. The full
firmware source is in my fork, at tag
[`v1.0.0`](https://github.com/aslucas-dev/Marlin/tree/v1.0.0).

## The problem

The printer ran Marlin without network support, and enabling the WiFi module
exposed several separate failures on this board:

| Symptom | Root cause | Fix |
|---|---|---|
| Build failed: RAM overflow of 6424 bytes on the F103VE | The Color UI drawing buffer plus the WiFi buffers did not fit in 64 KB | [Reduce `TFT_BUFFER_WORDS`](patches/0001-reduce-tft-buffer-words.patch) |
| `Link: not configured`; the board never heard the module | `WifiSerial::init` left `pin_rts` and `pin_cts` at `PA_0`, so `uart_init()` gave up silently | [Set both pins to `NC`](patches/0002-wifiserial-rts-cts-nc.patch) |
| Watchdog reset every 10 s with any card inserted | `manage_media()` mounted a card that `setup()` had already mounted, and the hang followed that second mount | [Clear SDIO registers on F1](patches/0003-clear-f1-sdio-registers.patch) and [skip the second mount](patches/0004-skip-second-mount.patch) |
| Example configuration rejected with BLTouch | `Z_MIN_ENDSTOP_HIT_STATE` stayed `LOW` | Configuration change |
| Z axis and extruder ran backwards | The example's TMC2209 settings did not match this machine | Configuration change |

## How it was diagnosed

- **Serial port:** I added a temporary `M587 D` report. USART1 had no clock and
  zeroed registers, while PA10 counted 1228 edges. The module was transmitting and
  the UART had never started, which pointed to initialization rather than wiring.
- **SD card:** a boot trace stopped inside `manage_media()` right after
  `Media present: -1 -> 1`. An empty card failed the same way, which ruled out the
  card contents.
- **Motion and sensors:** each axis and the extruder were checked against commanded
  moves on the machine, one at a time.

## A mistake worth recording

I first read `M119` as `filament: TRIGGERED` meaning "filament out" and inverted
`FIL_RUNOUT_STATE`. The firmware then saw a runout with filament loaded and ran
`M600` at the start of a print. The source settled it:
`print_es_state(!FILAMENT_IS_OUT())` means `TRIGGERED` is *filament present*, so the
original value was right. I reverted the change, and I now check what a reading
means in the source before changing firmware because of it.

## Results

Tested on one printer on 2026-10-31.

| Test | Result |
|---|---|
| WiFi connection and reconnection after restart | Pass |
| Commands over TCP port 8080 | Pass |
| 2 MB upload | 26 s, about 77 kB/s, with matching size; an earlier 2 MB upload was byte-identical |
| Complete print sent over WiFi | Finished in 8 min 47 s with no errors; purge lines and part approved |
| Temperature during the print (after the first layers) | Nozzle 229.4 to 231.1 °C, bed 79.6 to 80.7 °C |
| Card removal and reinsertion with the printer on | Pass |
| Firmware size | RAM 85.4%, flash 56.4% |

Sanitized logs are in [`evidence/`](evidence).

## Sending a file

There is no upload form on the module's web page. Use the HTTP endpoint with the
printer idle:

```
./scripts/upload.sh 192.0.2.10 part.gcode
```

Then start the print from the printer's screen.

## Building

```
git clone --branch v1.0.0 https://github.com/aslucas-dev/Marlin.git
./scripts/build.sh Marlin
```

Copy the resulting `Robin_nano35.bin` to the SD card and power on. **Back up the
card first, and check every axis and the extruder before printing:** direction,
drivers and probe offset can differ between machines. Then set your network:

```
M587 A0 S"YourNetwork" P"YourPassword"
M500
```

The [`config/`](config) files are the ones used at `v1.0.0`. The probe offset in
use on my machine is `M851 Z-1.77`, saved in its settings; the default in those
files is still `-0.6`.

## Known limitations

- Only one network is stored. When it is unavailable, the module opens its own
  access point **with no password**.
- Commands sent to port 8080 during an upload are written into the file.
- Files of 58 and 200 bytes returned HTTP 200 but were not saved; 1100 bytes and
  larger worked.
- `M23` with a long file name over the network fails with `file.open failed`.
- A real filament runout during a print has not been tested.
- Nothing here has been tested on any other machine.

## Status upstream

The patches are based on Marlin
[`22abaad`](https://github.com/MarlinFirmware/Marlin/commit/22abaad533b0230397f3ef1bbb4798e3e02c1da0).
They have not been submitted yet. Marlin's WiFi module support itself comes from
the Marlin project; this work fixes what kept it from running on this setup.

## Credits and license

Built on [Marlin Firmware](https://github.com/MarlinFirmware/Marlin) and its
[Configurations](https://github.com/MarlinFirmware/Configurations) examples.
Developed with AI assistance (Claude Code) and tested on the real printer.

Licensed under [GPLv3](LICENSE), the same license as Marlin.
