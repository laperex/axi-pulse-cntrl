# axi-pulse-cntrl

A minimal but complete xviv project targeting the **Basys3** (Artix-7 `xc7a35tcpg236-1`). It demonstrates the full xviv workflow — from a custom AXI4-Lite IP through block design, synthesis, and embedded firmware — all driven from a single `project.toml`.

---

## What this project does

A MicroBlaze soft-core processor controls a configurable pulse generator over AXI4-Lite. The firmware lets you adjust the pulse period and polarity using the four on-board buttons, and mirrors the pulse state to the LEDs.

| Output | Pin | Description |
|--------|-----|-------------|
| `pulse_out_0` | LD4 (W18) | The generated pulse |
| `gpio_rtl_0[3:0]` | LD3–LD0 | Speed indicator + pulse mirror |

| Input | Pin | Function |
|-------|-----|---------|
| btnU (T18) | `gpio_rtl_1[3]` | Halve period (faster) |
| btnD (U18) | `gpio_rtl_1[0]` | Double period (slower) |
| btnL (T17) | `gpio_rtl_1[2]` | Toggle output invert |
| btnR (U17) | `gpio_rtl_1[1]` | Toggle enable |

UART output (115200 baud, USB–UART bridge) logs each button event.

---

## Prerequisites

- Python 3.11+
- Vivado 2024.x (with Vitis / XSCT) on `PATH`, or set the environment variable:
  ```sh
  export XVIV_VIVADO_SOURCE_SCRIPT=/tools/Xilinx/Vivado/2024.1/settings64.sh
  ```
- A Basys3 board connected over JTAG

Install xviv:

```sh
pip install xviv
```

---

## Project layout

```
.
├── project.toml                    # Single source of truth for the build
├── constraints/
│   └── system.xdc                  # Pin assignments for Basys3
├── srcs/
│   ├── rtl/
│   │   ├── if_axi_lite.sv          # Parameterised AXI4-Lite interface
│   │   └── axi_pulse_cntrl.sv      # Custom IP RTL
│   ├── sim/
│   │   └── tb_axi_pulse_cntrl.sv   # Custom IP testbench
│   └── sw/
│       └── main.c                  # MicroBlaze firmware
└── scripts/
    └── xviv/
        └── bd/
            └── bd_mblaze_system.tcl   # Block design snapshot (version-controlled)
```

`build/` is produced by xviv and should be gitignored — everything in it is fully reproducible from the sources above.

---

## How the project is described in `project.toml`

Understanding `project.toml` is the key to understanding any xviv project. The sections below walk through this project's file with annotations.

### `[project]`

```toml
[project]
build_dir = "build"
```

All generated artefacts land under `build/`. xviv never writes outside this directory (except for the BD TCL snapshot under `scripts/xviv/`).

### `[[fpga]]`

```toml
[[fpga]]
name      = "main"
fpga_part = "xc7a35tcpg236-1"
```

Declares the target device. The `name` field is a reference handle used by other sections. Multiple `[[fpga]]` entries are allowed; the first is the default.

### `[[ip]]` — packaging the custom IP

```toml
[[ip]]
name    = "axi_pulse_cntrl"
sources = [
    "./srcs/rtl/if_axi_lite.sv",
    "./srcs/rtl/axi_pulse_cntrl.sv"
]
```

Points xviv at the RTL source files for the custom IP. Running `xviv create --ip axi_pulse_cntrl` invokes the Vivado IP Packager and registers the result in the project's local IP repository under `build/ip/`. Once packaged, the IP appears in the Vivado IP catalog as `xviv.org:xviv:axi_pulse_cntrl:1.0` and can be instantiated in block designs.

### `[[wrapper]]` — interface flattening

```toml
[[wrapper]]
ip      = "axi_pulse_cntrl"
sources = [
    "./srcs/rtl/if_axi_lite.sv",
    "./srcs/rtl/axi_pulse_cntrl.sv"
]
```

The RTL uses a SystemVerilog `interface` port (`if_axi_lite.slave`). Vivado's block design cannot connect interface-typed ports directly — it expects individual AXI signals. The `[[wrapper]]` section tells xviv to auto-generate a thin wrapper module that flattens the interface into the discrete signals Vivado expects, using `pyslang` to parse the source. The wrapper is transparently folded into the packaged IP.

### `[[bd]]` — the block design

```toml
[[bd]]
name = "bd_mblaze_system"
```

Declares a block design. The TCL snapshot at `scripts/xviv/bd/bd_mblaze_system.tcl` is the source of truth. Running `xviv create --bd bd_mblaze_system` recreates the full block design non-interactively from that snapshot on any machine, without needing a saved Vivado project file.

The block design contains:
- MicroBlaze processor with local BRAM (32 KB)
- MDM debug module
- Clock wizard: 100 MHz → 50 MHz
- AXI SmartConnect (1 master → 3 slaves)
- `axi_pulse_cntrl_0` — the custom IP (at `0x44A00000`)
- AXI UARTlite (at `0x40600000`, 115200 baud)
- AXI GPIO — dual channel, LEDs out / buttons in (at `0x40000000`)

### `[[synth]]` — synthesis and implementation run

```toml
[[synth]]
bd           = "bd_mblaze_system"
constraints  = ["./constraints/system.xdc"]
run_synth    = true
run_opt      = true
run_place    = true
run_phys_opt = true
run_route    = true
synth_incremental = true
impl_incremental = true
route_report_timing_summary = true
synth_report_utilization    = true
route_report_drc            = true
```

Drives the full Vivado implementation pipeline. Each `run_*` flag is independently toggleable, so you can resume from a checkpoint without re-running earlier stages. The three `*_report_*` flags enable post-route timing, utilization, and DRC reports under `build/synth/bd_mblaze_system/reports/`.

### `[[platform]]` and `[[app]]` — embedded software

```toml
[[platform]]
name = "mb_platform"
bd   = "bd_mblaze_system"
cpu  = "microblaze_0"
os   = "standalone"

[[app]]
name     = "firmware"
platform = "mb_platform"
template = "empty_application"
sources  = ["./srcs/sw/main.c"]
```

`[[platform]]` generates a BSP from the XSA produced by synthesis, targeting `microblaze_0` with the standalone (bare-metal) OS. `[[app]]` creates a Vitis application project from the `empty_application` template and builds it against that BSP, compiling `main.c` into an ELF.

### `[[simulation]]` — testbench simulation

```toml
[[simulation]]
name      = "tb_axi_pulse_cntrl"
top       = "tb_axi_pulse_cntrl"
backend   = "xsim"
timescale = "1ns/1ps"
sources   = [
    "./srcs/rtl/if_axi_lite.sv",
    "./srcs/rtl/axi_pulse_cntrl.sv",
    "./srcs/sim/tb_axi_pulse_cntrl.sv"
]
```

---

## Build walkthrough

The steps below describe the recommended sequence for a clean build from source.

### 1. Package the custom IP

```sh
xviv create --ip axi_pulse_cntrl --regenerate
```

This invokes the Vivado IP Packager in batch mode. The packaged IP lands in `build/ip/axi_pulse_cntrl/` and is added to the project IP catalog automatically. You only need to re-run this step if the RTL source changes.

`--regenerate` automatically generates output products for all cores that instantiate this IP. This is useful when modifying the RTL of an IP used as a block design subcore, as it eliminates the need to run `xviv generate bd` separately.

### 2. Recreate the block design

```sh
xviv create --bd bd_mblaze_system --generate
```

Replays the TCL snapshot to rebuild the block design inside Vivado.

`--generate` generates output products (HDL wrappers, etc.) and returns immediately.

### 3. Run synthesis and implementation

```sh
xviv synth --bd bd_mblaze_system
```

Runs synth → opt → place → phys_opt → route and writes the bitstream to `build/synth/bd_mblaze_system/bd_mblaze_system.bit`. Checkpoints for each stage are saved under `build/synth/bd_mblaze_system/checkpoints/`.

To resume from an existing checkpoint (for example, after tweaking a constraint):

```sh
xviv synth --bd bd_mblaze_system --resume place
```

### 4. Build the BSP and firmware

```sh
xviv build --platform mb_platform
xviv build --app firmware --info
```

`--info` prints ELF section sizes after the build completes. The ELF lands at `build/app/firmware/firmware.elf`.

### 5. Program the board

Connect the Basys3 over USB, then run:

```sh
xviv program --platform mb_platform --app firmware
```

This configures the FPGA with the bitstream and loads the ELF over JTAG via XSCT. Open a serial terminal at 115200 baud to see the firmware log.

---

## The custom IP in detail

### Register map

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | CTRL | R/W | Bit 0: enable. Bit 1: invert output. |
| `0x04` | PERIOD | R/W | Counter period in clock cycles (min 1). |
| `0x08` | WIDTH | R/W | High-time in clock cycles. |
| `0x0C` | STATUS | RO | Bit 0: current `pulse_out` value. |

At 50 MHz, the default period of 50,000,000 cycles gives a 1 Hz pulse with a 50% duty cycle.

### RTL structure

`if_axi_lite.sv` defines a parameterised SystemVerilog interface with `slave` and `master` modports. `axi_pulse_cntrl.sv` instantiates that interface as a slave and implements two independent AXI state machines (one for writes, one for reads), plus a free-running counter that generates `raw_pulse`, which is optionally inverted before being driven to `pulse_out`.

The `[[wrapper]]` entry in `project.toml` tells xviv to use `pyslang` to parse the source and emit a flat wrapper module, so the IP integrates cleanly with Vivado's block design AXI connection automation.

### Firmware

`main.c` sets the initial period to 1 s (50,000,000 cycles) and enters a polling loop. Button edges are detected by comparing the current and previous GPIO reads. Each button event writes to the appropriate IP register and prints a status line over UART. The pulse state is polled from `STATUS` and reflected on the LEDs on each change.

---

## Edit in GUI

### Block design

```sh
# Open in the Vivado GUI
xviv edit --bd bd_mblaze_system

# Open in terminal as interactive Tcl mode
xviv edit --bd bd_mblaze_system --nogui

# Run before synthesis if the block design has been modified
xviv generate --bd bd_mblaze_system

# Force-generate output products, even if xviv flags them as stale
xviv generate --bd bd_mblaze_system -force
```

### IP

```sh
# Open the IP Packager in the Vivado GUI
xviv edit --ip axi_pulse_cntrl

# Open in terminal as interactive Tcl mode
xviv edit --ip axi_pulse_cntrl --nogui
```

---

## Useful commands

```sh
# Inspect any post-route checkpoint in the Vivado GUI
xviv open --dcp build/synth/bd_mblaze_system/checkpoints/route.dcp

# Re-open the block design editor
xviv create --bd bd_mblaze_system --edit

# Dry-run: print the TCL xviv would send to Vivado without executing
xviv synth --bd bd_mblaze_system --dry-run

# Re-program just the FPGA (e.g. after a bitstream-only rebuild)
xviv program --platform mb_platform --app firmware

# Reset the processor without reprogramming
xviv processor --reset
```

### Simulation

```sh
# Run the specified simulation target
xviv simulate --target tb_axi_pulse_cntrl

# Open the waveform in the Vivado waveform GUI
xviv open --wdb tb_axi_pulse_cntrl

# Reload an already-open waveform after re-running simulation
xviv reload --wdb tb_axi_pulse_cntrl
```
