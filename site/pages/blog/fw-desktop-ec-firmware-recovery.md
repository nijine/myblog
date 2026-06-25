---
title: Recovering a Bricked Framework Desktop EC via SWD
date: 'Wed Jun 25 2026'
description: How I recovered a Framework Desktop that wouldn't power on by reflashing the Nuvoton NPCX993 EC firmware over SWD using a Raspberry Pi Pico 2W and OpenOCD.
tags:
  - framework
  - embedded
  - hardware
  - reverse-engineering
  - swd
  - openocd
---

A few days ago I managed to brick the Embedded Controller (EC) firmware on my Framework Desktop — the system wouldn't power on at all when I pressed the power button. This is a write-up of how I traced down the right chip, found the debug header, and recovered the system using a Raspberry Pi Pico 2W, OpenOCD, and a backup I'd made with `ectool`.

## Background

The EC on a modern laptop or desktop motherboard is a small microcontroller that handles low-level functions: power sequencing, thermal management, the power button, and so on. If its firmware gets corrupted, the system can end up in a state where it partially boots — LEDs light up, standby power is present — but the main system never comes on. That's exactly what happened here.

Before things went sideways I had taken a backup using `ectool`:

```bash
ectool flashread 0 524288 ec_backup_2026_06_23.bin
```

That produced a 512KB binary. Getting it back onto the EC turned out to be a more interesting journey than I expected.

## Finding the EC

The first challenge was figuring out which chip was actually the EC. The Framework Desktop schematic PDF (available at the [Framework-Desktop GitHub repo](https://github.com/FrameworkComputer/Framework-Desktop)) doesn't label anything as "EC" or "Embedded Controller" — so I had to go hunting by chip marking.

A few red herrings along the way:

- **W25X20CLIG** — a Winbond 2Mbit SPI NOR flash. Looked promising, but at 256KB it's too small for a 512KB firmware image, and it turned out to be sitting right next to a **GL3590** USB hub controller. It's that chip's config flash, not the EC's.
- **MPS2515** — a power management IC, not the EC.

The actual EC was a **Nuvoton NPCX993FA0BX**, hiding under the M.2 SSD slot area. Once I found it, the nearby **JECDB1** debug header became the obvious path forward.

## The JECDB1 Header

The JECDB1 header is a 10-pin connector that provides SWD (Serial Wire Debug) access to the EC. It's not populated from the factory — just bare pads — but the pinout is documented in the [Framework EmbeddedController repo README](https://github.com/FrameworkComputer/EmbeddedController):

| Pin | Signal |
|-----|--------|
| 1 | EC_VCC_3.3V |
| 2 | TDI |
| 3 | TMS (SWDIO) |
| 4 | CLK (SWDCLK) |
| 5 | TDO |
| 6 | UART_TX |
| 7 | UART_RX |
| 8 | (not connected) |
| 9 | EC_RESETI |
| 10 | GND |

Note: this pinout is documented for the Framework Laptop mainboards (hx20/hx30). The Desktop uses a different EC (NPCX993 vs MEC1521), but the JECDB1 header layout appears to be the same. I confirmed pin 1 as 3.3V and pin 10 as GND with a multimeter before connecting anything.

For a minimal SWD reflash you only need **pins 1, 3, 4, and 10** — VCC, SWDIO, SWDCLK, and GND. Since the board already has standby power from the ATX PSU's 5VSB rail, I skipped the VCC connection entirely and just used pins 3, 4, and 10.

## The NPCX993FA0BX

The NPCX993 is a Nuvoton ARM Cortex-M4 based EC, part of their NPCX9 series. Crucially, it has **512KB of on-die flash** — which is why there's no separate external flash chip for the EC firmware, and why the 512KB `ectool` backup made sense. The firmware lives entirely inside the chip at flash address `0x64000000`.

## Hardware Setup

I used a **Raspberry Pi Pico 2W** running [Picoprobe](https://github.com/raspberrypi/picoprobe) firmware as the SWD debug probe. Flash it by holding BOOTSEL while plugging in, then dragging the Picoprobe UF2 onto the mass storage device that appears.

Wiring from Pico to JECDB1:

| Pico Pin | JECDB1 Pin | Signal |
|----------|------------|--------|
| GP2 | Pin 4 | SWDCLK |
| GP3 | Pin 3 | SWDIO |
| GND | Pin 10 | GND |

Do **not** connect the Pico's 3.3V to JECDB1 pin 1 if the board is already powered — you'd be connecting two power supplies together.

## OpenOCD

Install OpenOCD on Bazzite (Fedora-based, uses rpm-ostree):

```bash
sudo rpm-ostree install openocd
# reboot to apply
```

Check that the NPCX target config is present:

```bash
find /usr/share/openocd -name "*npcx*"
# should return: .../scripts/target/npcx.cfg
```

Connect to the EC:

```bash
openocd -f interface/cmsis-dap.cfg -f target/npcx.cfg
```

If everything is wired correctly you'll see something like:

```
Info : CMSIS-DAP: SWD supported
Info : SWD DPIDR 0x...
Info : NPCX_M4.cpu ...
Info : Listening on port 3333 for gdb connections
```

## Flashing the Firmware

With OpenOCD running, open a second terminal and connect to its command interface:

```bash
nc localhost 4444
```

Then flash the backup image. The key detail that took some digging to find: the NPCX993's flash is mapped at **`0x64000000`**, not `0x00000000`. Using the wrong address results in OpenOCD reporting zero bytes written with no error.

```
reset halt
flash write_image erase /path/to/ec_backup_2026_06_23.bin 0x64000000
reset run
```

A successful flash looks like:

```
auto erase enabled
wrote 524288 bytes from file ec_backup_2026_06_23.bin in 17.038258s (30.050 KiB/s)
```

524288 bytes = exactly 512KB. After `reset run`, disconnecting the Pico and pressing the board power button, the system came back up normally. Phew!

## Key Takeaways

A few things I couldn't find documented anywhere before going through this process:

- The Framework Desktop EC is a **Nuvoton NPCX993FA0BX**, not the MEC1521 used in the laptops.
- The EC firmware lives in **on-die flash at `0x64000000`** — there is no external SPI flash chip for the EC.
- The **JECDB1 header pinout** from the laptop mainboard README works for the Desktop as well.
- OpenOCD's `npcx.cfg` already declares the correct flash bank — you just need to target the right address when writing.
- The W25X20CLIG flash chip near the USB area belongs to the **GL3590 USB hub controller**, not the EC.

Hopefully this saves someone else a few hours of digging. If you're attempting this yourself, make sure you have a good `ectool` backup before experimenting with EC firmware.

## References

- [Framework Desktop GitHub repo](https://github.com/FrameworkComputer/Framework-Desktop)
- [Framework EmbeddedController repo](https://github.com/FrameworkComputer/EmbeddedController) (JECDB pinout in README)
- [Picoprobe firmware](https://github.com/raspberrypi/picoprobe)
- [OpenOCD](https://openocd.org)
