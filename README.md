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
| Watchdog reset every 10 s with any card inserted | The STM32F1 HAL has no SDIO reset, so mounting the card a second time (at boot, or with `M21`) hung | [Clear SDIO registers on F1](patches/0003-clear-f1-sdio-registers.patch); `v1.0.0` also [skips the second mount at boot](patches/0004-skip-second-mount.patch), which later tests showed is not needed |
| Example configuration rejected with BLTouch | `Z_MIN_ENDSTOP_HIT_STATE` stayed `LOW` | Configuration change |
| Z axis and extruder ran backwards | The example's TMC2209 settings did not match this machine | Configuration change |

## How it was diagnosed

- **Serial port:** I added a temporary `M587 D` report. USART1 had no clock and
  zeroed registers, while PA10 counted 1228 edges. The module was transmitting and
  the UART had never started, which pointed to initialization rather than wiring.
- **SD card:** a boot trace stopped inside `manage_media()` right after
  `Media present: -1 -> 1`. An empty card failed the same way, which ruled out the
  card contents. Flashing each half of the fix on its own later showed the cause:
  skipping the second mount let the board boot, but the next `M21` still reset it;
  clearing the SDIO registers alone fixed both.
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

## Changing networks

Only one network is stored. When it is unavailable, the module opens its own
access point **with no password**. Tested alternatives:

- `M587 A0 S"Network" P"password"` and `M500` join another network. Names with
  spaces work.
- `M587 A1 S"Name" P"password"` and `M500` make the printer host its own network
  **with** a password (WPA2), reachable at 192.168.4.1.
- The module's web page can change the network too, but Marlin restores its own
  saved network at the next power-on. The page also shows the password in plain
  text and sends it in the URL.

## Known limitations

- Commands sent to port 8080 during an upload are written into the file.
- Files of 58 and 200 bytes returned HTTP 200 but were not saved; 1100 bytes and
  larger worked.
- In `v1.0.0`, `M20 <path>` and `M23` sent over the network fail, and a USB host
  gets an unsolicited `ok T:` line every 5 seconds. Both are fixed in Marlin
  `bugfix-2.1.x` (see below), but not yet in a release built here.
- After `M24` sent over the network, the WiFi side kept reporting `PRINTING` while
  Marlin was idle, which blocks file commands over WiFi until a restart. Not yet
  understood.
- A real filament runout during a print has not been tested.
- Nothing here has been tested on any other machine.

## Status upstream

The patches here are based on Marlin
[`22abaad`](https://github.com/MarlinFirmware/Marlin/commit/22abaad533b0230397f3ef1bbb4798e3e02c1da0).
Fixes sent to Marlin, each tested on this printer against the current
`bugfix-2.1.x`:

| Pull request | Fix | Status |
|---|---|---|
| [#28784](https://github.com/MarlinFirmware/Marlin/pull/28784) | MKS WiFi serial init leaving RTS/CTS on `PA_0` | Merged 2026-11-03 |
| [#28785](https://github.com/MarlinFirmware/Marlin/pull/28785) | STM32F1 SDIO hang when the card is mounted again | Merged 2026-11-03 |
| [#28786](https://github.com/MarlinFirmware/Marlin/pull/28786) | MKS WiFi `M20`, `M23` and `M28` reading their arguments from the wrong place | Merged 2026-11-03 |
| [#28787](https://github.com/MarlinFirmware/Marlin/pull/28787) | Unsolicited `ok T:` on the USB port from the module's temperature polls | Merged 2026-11-03 |
| [#28811](https://github.com/MarlinFirmware/Marlin/pull/28811) | MKS WiFi `M23` with the long name of an uploaded file | Merged 2026-11-09 |

After #28786, another contributor fixed the same argument bug in `M998`
([#28789](https://github.com/MarlinFirmware/Marlin/pull/28789)).

Marlin's WiFi module support itself comes from the Marlin project; this work fixes
what kept it from running on this setup.

## Credits and license

Built on [Marlin Firmware](https://github.com/MarlinFirmware/Marlin) and its
[Configurations](https://github.com/MarlinFirmware/Configurations) examples.
Developed with AI assistance (Claude Code) and tested on the real printer.

Licensed under [GPLv3](LICENSE), the same license as Marlin.
