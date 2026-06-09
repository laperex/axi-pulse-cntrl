# axi-pulse-cntrl

AXI4-Lite configurable pulse-generator demo for the **Basys3** (`xc7a35tcpg236-1`).

A custom AXI4-Lite peripheral drives a free-running pulse output. A **MicroBlaze** soft-core processor controls the IP over AXI — the four on-board buttons adjust period, polarity, and enable state at runtime; LEDs mirror pulse activity and speed. All button events are logged over UART.

Built and managed with [xviv](https://github.com/laperex/xviv).

---

## System architecture

```mermaid
flowchart LR
    subgraph board["Basys3"]
        clk["clk_100MHz\n100 MHz"]
        btnC["btnC — reset"]
        btns["btnU / D / L / R"]
        leds["LD3–LD0\nspeed indicator"]
        ld4["LD4  pulse_out_0"]
        uart_io["USB–UART\n115200 baud"]
    end

    subgraph bd["bd_mblaze_system"]
        clk_wiz["clk_wiz\n100 → 50 MHz"]
        rst["proc_sys_reset"]
        mb["microblaze_0\n32-bit soft core"]
        bram["LMB BRAM\n32 KB"]
        mdm["MDM\nJTAG debug"]
        smc["AXI SmartConnect\n1M → 3S"]

        subgraph ip_block["axi_pulse_cntrl_0  (custom IP @ 0x44A00000)"]
            pulse_core["axi_pulse_cntrl\nAXI4-Lite slave + counter"]
        end

        gpio["axi_gpio_0\nch1: LEDs / ch2: buttons\n@ 0x40000000"]
        uart["axi_uartlite_0\n@ 0x40600000"]
    end

    clk      --> clk_wiz
    btnC     --> clk_wiz
    clk_wiz  -- "50 MHz" --> rst
    rst      -- "aresetn" --> mb & ip_block & gpio & uart & smc
    clk_wiz  -- "50 MHz"  --> mb & ip_block & gpio & uart & smc
    mb      <-->|"LMB"| bram
    mb      <-->|"MDM"| mdm
    mb       -->|"M_AXI_DP"| smc
    smc      --> ip_block
    smc      --> gpio
    smc      --> uart
    btns     --> gpio
    gpio     --> leds
    ip_block --> ld4
    uart     --> uart_io
```

### Board I/O

| Signal | Pin | Direction | Function |
|--------|-----|-----------|---------|
| `pulse_out_0` | LD4 · W18 | Output | Generated pulse |
| `gpio_rtl_0[3:0]` | LD3–LD0 | Output | Speed indicator + pulse mirror |
| `gpio_rtl_1[3]` | btnU · T18 | Input | Halve period (faster) |
| `gpio_rtl_1[2]` | btnL · T17 | Input | Toggle output invert |
| `gpio_rtl_1[1]` | btnR · U17 | Input | Toggle enable |
| `gpio_rtl_1[0]` | btnD · U18 | Input | Double period (slower) |
| `uart_0_txd` | A18 | Output | UART TX |

---

## Project structure

```
axi-pulse-cntrl/
├── project.toml                    # xviv project config
├── constraints/
│   └── system.xdc                  # Basys3 pin assignments (LVCMOS33, false paths)
├── srcs/
│   ├── rtl/
│   │   ├── if_axi_lite.sv          # parameterised AXI4-Lite SV interface
│   │   └── axi_pulse_cntrl.sv      # custom IP — AXI4-Lite slave + pulse counter
│   ├── sim/
│   │   └── tb_axi_pulse_cntrl.sv   # IP-level testbench, 7 test groups
│   └── sw/
│       └── main.c                  # MicroBlaze bare-metal firmware
└── scripts/
    └── xviv/bd/
        └── bd_mblaze_system.tcl    # block design TCL snapshot (version-controlled)
```

`build/` is produced by xviv and is fully reproducible from the sources above.

### Block design hierarchy

```mermaid
graph TD
    bd["<b>bd_mblaze_system</b><br/><i>Vivado Block Design</i>"]
    clkwiz["clk_wiz<br/><i>Clocking Wizard 6.0</i>"]
    rst["proc_sys_reset<br/><i>Processor System Reset 5.0</i>"]
    mb["microblaze_0<br/><i>MicroBlaze 11.0</i>"]
    bram["microblaze_0_local_memory<br/><i>LMB BRAM 32 KB</i>"]
    mdm["mdm_0<br/><i>MDM 3.2</i>"]
    smc["axi_smc<br/><i>AXI SmartConnect 1.0  — 1M → 3S</i>"]
    ip["axi_pulse_cntrl_0<br/><i>pyslang-generated wrapper</i>"]
    core["axi_pulse_cntrl<br/><i>IP RTL top</i>"]
    gpio["axi_gpio_0<br/><i>AXI GPIO 2.0  — dual-channel</i>"]
    uart["axi_uartlite_0<br/><i>AXI UARTlite 2.0</i>"]

    bd --> clkwiz & rst & mb & smc & ip & gpio & uart
    mb --> bram & mdm
    ip --> core
```

---

## Register map

| Offset | Name | Access | Bits | Description |
|--------|------|--------|------|-------------|
| `0x00` | `CTRL` | R/W | `[1:0]` | Bit 0: enable. Bit 1: invert output. |
| `0x04` | `PERIOD` | R/W | `[31:0]` | Counter period in clock cycles (min 1). Default 50,000,000 → 1 Hz at 50 MHz. |
| `0x08` | `WIDTH` | R/W | `[31:0]` | High-time in clock cycles. Default 25,000,000 → 50% duty cycle. |
| `0x0C` | `STATUS` | RO | `[0]` | Current `pulse_out` value. Writes ignored. |

Writes to `PERIOD` with value `0` are clamped to `1`. The counter and `raw_pulse` reset to zero whenever `CTRL[0]` (enable) is cleared. `pulse_out = invert ? ~raw_pulse : raw_pulse`.

---

## AXI4-Lite bus

### Channel directions

```mermaid
flowchart LR
    M["microblaze_0<br/>(Master)"]
    S["axi_pulse_cntrl<br/>(Slave)"]

    M -->|"AW — awaddr / awprot / awvalid / awready"| S
    M -->|"W  — wdata / wstrb / wvalid / wready"| S
    S -->|"B  — bresp / bvalid / bready"| M
    M -->|"AR — araddr / arprot / arvalid / arready"| S
    S -->|"R  — rdata / rresp / rvalid / rready"| M
```

### Write channel FSM

`awready` and `wready` are asserted together in `WR_IDLE`; the IP requires both AW and W to arrive simultaneously.

```mermaid
stateDiagram-v2
    direction LR
    [*] --> WR_IDLE

    WR_IDLE --> WR_RESP : awvalid && wvalid\napply write, assert bvalid & bresp=OKAY
    WR_RESP --> WR_RESP : !bready\nhold bvalid
    WR_RESP --> WR_IDLE : bvalid && bready\nclear bvalid
```

> Writes to `STATUS` (`0x0C`) fall through the `default` branch and are silently discarded.

### Read channel FSM

```mermaid
stateDiagram-v2
    direction LR
    [*] --> RD_IDLE

    RD_IDLE --> RD_DATA : arvalid\nlatch rdata from register mux, assert rvalid & rresp=OKAY
    RD_DATA --> RD_DATA : !rready\nhold rvalid
    RD_DATA --> RD_IDLE : rvalid && rready\nclear rvalid
```

`rdata` mux: `0x00` → `reg_ctrl` · `0x04` → `reg_period` · `0x08` → `reg_width` · `0x0C` → `{31'b0, pulse_out}`.

---

## Custom IP and wrapper generation

`axi_pulse_cntrl` uses a SystemVerilog interface port (`if_axi_lite.slave s_axi`). Vivado's IP Packager cannot infer AXI bus interfaces from SV interface ports, so `[[wrapper]]` in `project.toml` instructs xviv to generate a flattened wrapper via pyslang, exposing all signals as scalar ports (`s_axi_awaddr`, `s_axi_wdata`, …). This wrapper is packaged as `xviv.org:xviv:axi_pulse_cntrl:1.0` and instantiated in the block design as `axi_pulse_cntrl_0`.

```mermaid
flowchart LR
    src["RTL sources\nif_axi_lite.sv\naxi_pulse_cntrl.sv"]
    pyslang["pyslang\nAST port flattening"]
    wrapper["axi_pulse_cntrl_wrapper.sv\nscalar AXI ports\ns_axi_awaddr, s_axi_wdata, …"]
    packager["Vivado IP Packager\ninfers AXI interfaces\nfrom port-name patterns"]
    catalog["IP Catalog\nxviv.org:xviv:\naxi_pulse_cntrl:1.0"]
    bd_inst["Block Design\naxi_pulse_cntrl_0\n@ 0x44A00000"]

    src       -->|"xviv create --ip"| pyslang
    pyslang   --> wrapper
    wrapper   --> packager
    packager  --> catalog
    catalog   --> bd_inst
```

```sh
# Package the custom IP (generates wrapper, runs IP Packager)
# --regenerate re-generates output products for all cores using this IP
xviv create --ip axi_pulse_cntrl --regenerate
```

---

## Build flow

```mermaid
flowchart TD
    ip_cmd["xviv create --ip axi_pulse_cntrl --regenerate"]
    bd_cmd["xviv create --bd bd_mblaze_system --generate"]
    synth["synth_design\nbd_mblaze_system HD wrapper"]
    opt["opt_design"]
    place["place_design"]
    phys["phys_opt_design"]
    route["route_design"]
    bit["write_bitstream\nbuild/synth/bd_mblaze_system/bd_mblaze_system.bit"]
    rpts["timing_summary\nutilization\nDRC"]
    crplat["xviv create --platform mb_platform\ngenerate BSP workspace from XSA"]
    bldplat["xviv build --platform mb_platform\ncompile BSP"]
    crapp["xviv create --app firmware\nscaffold Vitis app"]
    bldapp["xviv build --app firmware\ncompile ELF → executable.elf"]
    prog["xviv program --platform mb_platform --app firmware\nconfigure FPGA + load ELF via XSCT"]

    ip_cmd  -->|"packaged IP → build/ip/"| bd_cmd
    bd_cmd  --> synth
    synth   --> opt --> place --> phys --> route
    route   --> bit
    route   --> rpts
    bit     --> crplat --> bldplat --> crapp --> bldapp --> prog
```

### Step-by-step

```sh
# 1. Package the custom IP
xviv create --ip axi_pulse_cntrl --regenerate

# 2. Recreate and elaborate the block design
xviv create --bd bd_mblaze_system --generate

# 3. Synthesis and implementation
xviv synth --bd bd_mblaze_system

# 4. Create Vitis BSP workspace from the XSA, then compile it
xviv create --platform mb_platform
xviv build   --platform mb_platform

# 5. Scaffold the firmware app, then compile the ELF
xviv create --app firmware
xviv build   --app firmware --info

# 6. Program the board (FPGA bitstream + ELF over JTAG)
xviv program --platform mb_platform --app firmware
```

Open a serial terminal at **115200 baud** to see firmware log output.

Outputs in `build/`:

```
synth/bd_mblaze_system/
├── bd_mblaze_system.bit
├── bd_mblaze_system.xsa
├── checkpoints/{synth,place,route}.dcp
└── reports/
    ├── synth_report_utilization_file.rpt
    ├── route_report_timing_summary_file.rpt
    └── route_report_drc_file.rpt
app/firmware/
└── executable.elf
```

### Incremental builds

```sh
# Resume from the latest available checkpoint
xviv synth --bd bd_mblaze_system --resume auto

# Constraint changed only — skip to write_bitstream
xviv synth --bd bd_mblaze_system --resume route

# RTL or BD changed — load synth.dcp, re-run from opt_design onward
xviv synth --bd bd_mblaze_system --resume synth
```

---

## Simulation

IP-level testbench (`xsim`, 7 test groups · 20 ns clock · `1ns/1ps` timescale):

| Group | Description |
|-------|-------------|
| Test 1 | `pulse_out` held low after reset (disabled by default) |
| Test 2 | `PERIOD` and `WIDTH` write / readback |
| Test 3 | Rising and falling edges appear after `CTRL_ENABLE` |
| Test 4 | `STATUS[0]` mirrors `pulse_out` on both edges |
| Test 5 | `CTRL_INVERT` flips polarity; edges still present |
| Test 6 | Clearing `CTRL_ENABLE` holds `pulse_out` low across ≥ 4 periods |
| Test 7 | Write `PERIOD = 0` clamped to 1 in register |

```sh
# Run the simulation
xviv simulate --target tb_axi_pulse_cntrl

# Open waveform in Vivado GUI
xviv open --wdb tb_axi_pulse_cntrl

# Reload an already-open waveform after re-running simulation
xviv reload --target tb_axi_pulse_cntrl
```

---

## Edit in GUI

```sh
# Block design — open in Vivado GUI / interactive Tcl
xviv edit --bd bd_mblaze_system
xviv edit --bd bd_mblaze_system --nogui

# Regenerate output products after editing
xviv generate --bd bd_mblaze_system
xviv generate --bd bd_mblaze_system --force  # force even if marked up-to-date

# IP Packager — open in Vivado GUI / interactive Tcl
xviv edit --ip axi_pulse_cntrl
xviv edit --ip axi_pulse_cntrl --nogui
```

---

## Useful commands

```sh
# Dry-run — print the Tcl xviv would send to Vivado without executing
xviv synth --bd bd_mblaze_system --dry-run

# Inspect a post-route checkpoint in Vivado
xviv open --dcp build/synth/bd_mblaze_system/checkpoints/route.dcp

# Re-program without rebuilding (bitstream already present)
xviv program --platform mb_platform --app firmware

# Reset MicroBlaze without reprogramming the FPGA
xviv processor --reset
```

---

## Prerequisites

- Python ≥ 3.11
- Vivado 2024.x with Vitis / XSCT on `PATH`, or set:
  ```sh
  export XVIV_VIVADO_SOURCE_SCRIPT=/tools/Xilinx/Vivado/2024.1/settings64.sh
  ```
- Basys3 board connected over USB-JTAG

```sh
pip install xviv
```

---
