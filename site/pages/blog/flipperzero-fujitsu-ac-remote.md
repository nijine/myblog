---
title: Building a Fujitsu AC Remote for Flipper Zero
date: 2026/6/20
description: How I forked a Mitsubishi AC remote project to build a Fujitsu-compatible IR remote app for the Flipper Zero.
tag: flipper-zero,infrared,hvac,c,embedded
author: Dmitriy
---

# Building a Fujitsu AC Remote for Flipper Zero

A while back I picked up a [Flipper Zero](https://flipperzero.one/), and one of its coolest features is its built-in infrared transceiver. I've been using it to learn and replay signals from various remotes around the house, but I wanted to take things a step further and write a proper application that could act as a full-featured remote control for my Fujitsu **ASU9RLF** mini-split — the kind of thing you can actually use day-to-day instead of hunting down the OEM remote.

## Standing on the Shoulders of Giants

Rather than starting from scratch, I found a great open-source project by [achistyakov](https://github.com/achistyakov/flipperzero-mitsubishi-ac-remote) that implements a Mitsubishi AC remote for the Flipper Zero. The structure was solid — scenes, views, a dedicated HVAC library — and the overall architecture was exactly what I had in mind. I forked it and used it as the foundation for a Fujitsu-compatible version.

The Fujitsu protocol is quite different from Mitsubishi's, so while the application skeleton carried over well, essentially the entire IR communication layer needed to be rewritten. I used my **AR-RAH1U** remote (which uses the **AR-REB1E** protocol) as my source of truth, capturing signals with the Flipper and cross-referencing them against the Fujitsu protocol documentation I was able to track down.

## What the App Does

The finished app covers the full set of controls you'd expect from the real remote:

- **Power Toggle** — Toggles the unit on and off, with the current state displayed on-screen as "ON" or "OFF."
- **Temperature** — Steps in 2°F increments between **60°F and 88°F**. Internally, temperatures are converted to Celsius states and checksummed before being packed into the IR frame, since the Fujitsu protocol operates natively in Celsius.
- **HVAC Modes** — Heat, Cool, Dry, and Auto.
- **Fan Speeds** — Auto, Quiet, Low, Medium, and High.
- **Vertical Swing** — Toggle the vertical louver swing on or off.

One thing worth calling out is the **Fahrenheit temperature display**. I live in the US, so I wanted the UI to show °F even though the protocol speaks Celsius. This required building a mapping from each Fahrenheit step (60, 62, 64, ... 88) to its correct Celsius equivalent, computing the checksum for each, and embedding those as precomputed values in the library. It's a small thing but it makes daily use a lot more comfortable.

## Project Structure

The codebase follows the same general layout as the upstream project, adapted for Fujitsu:

- **`lib/hvac_fujitsu/`** — The core HVAC library: IR timings, state generation, checksum computation, and °F→°C mappings.
- **`scenes/`** — Application scenes (main menu, mode selection, fan speed, etc.), loaded from a settings-style format.
- **`views/`** — Panel view layouts for the Flipper's display.
- **`assets/`** — Pixel art assets, including a custom Fahrenheit indicator border frame I drew for the temperature display.

## Building and Installing

There are two ways to build and deploy the app depending on your Flipper's firmware situation.

### Standalone with `ufbt` (standard firmware)

```shell
# Build
ufbt build

# Deploy and launch on a connected Flipper Zero
ufbt launch
```

If you're running custom firmware and hit an `ApiTooNew` or `ApiTooOld` error, you need to point `ufbt` at the SDK that matches your firmware exactly:

```shell
# In your firmware repo, build and package the SDK
./fbt fw_dist

# Point ufbt at the local SDK zip
ufbt update --hw-target f7 --local /path/to/flipperzero-firmware/dist/f7-D/flipper-z-f7-sdk-local.zip

# Clean and relaunch
ufbt -c
ufbt launch
```

This comes up pretty frequently when running third-party firmware builds, so it's worth knowing about.

### Inside the Firmware Tree with `fbt` (custom firmware)

```shell
# Copy the project into the firmware's applications_user directory
cp -R flipperzero-fujitsu-ac-remote /path/to/flipperzero-firmware/applications_user/fujitsu_ac_remote

# Build and launch from the firmware repo root
./fbt launch APPSRC=fujitsu_ac_remote
```

## Adding It to Favorites

Once it's deployed, the `.fap` file lives at `/ext/apps/Infrared/fujitsu_ac_remote.fap` on the SD card. To pin it to your Favorites tab, you can either:

1. **Via the GUI**: Open the Archive → Apps → Infrared, highlight the app, long-press OK, and select **Pin**.
2. **Manually**: Edit `/ext/favorites.txt` on the SD card and append:
   ```
   /ext/apps/Infrared/fujitsu_ac_remote.fap
   ```

## Wrapping Up

This was a fun project that combined a bit of reverse-engineering, embedded C, and some pixel art. If you have a Fujitsu mini-split and a Flipper Zero sitting around, give it a try. The source is up on GitHub at [nijine/flipperzero-fujitsu-ac-remote](https://github.com/nijine/flipperzero-fujitsu-ac-remote).
