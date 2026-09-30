<!--
SPDX-FileCopyrightText: 2026 IObundle

SPDX-License-Identifier: GPL-3.0-only
-->

# ASIC flow (LibreLane)

This directory contains the files of the py2hwsw ASIC flow, which implements a
core/system from Verilog RTL to a GDSII layout using
[LibreLane](https://github.com/librelane/librelane) (the open source RTL-to-GDSII
flow, formerly known as OpenLane 2) and an open source PDK.

## Prerequisites

- `librelane` and `ciel` in the `PATH` (they are part of the py2hwsw nix
  environment, see `py2hwsw/lib/default.nix`).
- A PDK installed with `ciel`. The version of the PDK can be installed with:

  ```bash
  ciel fetch --pdk sky130A <version>
  ciel enable --pdk sky130A <version>
  ```

  The PDK version compatible with the `librelane` in use is the `sky130` value
  of the `pdk_hashes.yaml` file inside the `librelane` package.

## Usage

From the root of a build directory:

```bash
make asic-build   # run the flow (RTL to GDSII)
make asic-drc     # re-run only the DRC steps
make asic-lvs     # re-run only the LVS step
make asic-sta     # re-run only the post-layout STA
make asic-gui     # open the layout in the KLayout GUI
make asic-sim     # gate-level simulation of the post-place-and-route netlist
make asic-report  # write the results table to the documentation
make asic-clean   # remove the run directories
```

Or, from the `py2hwsw/lib` directory (sets up the build directory and runs the
flow on the given core):

```bash
make asic-build CORE=iob_timer BUILD_DIR=timer
```

Results of a run are stored under `runs/<run tag>/`, and the final views
(GDSII, LEF, DEF, netlists, reports) under `runs/<run tag>/final/`.

## Gate-level simulation

`make asic-sim` simulates the post-place-and-route netlist of the implemented
module with the core's testbench, using the standard cell simulation models of
the PDK (`hardware/asic/<PDK>/sim.mk`). The netlist is post-processed by
`gate_sim_prep.py`, which ties the power and ground nets of the place-and-route
netlist (which are top level ports, and are not part of the RTL version of the
module).

The testbench (`ASIC_TB`, by default `hardware/simulation/src/$(NAME)_tb.v`)
must instantiate the module that was implemented, and the simulation must be
driven by the same stimuli as in RTL simulation.

The top module of a core is not always the one that has a testbench: for
example, the testbench of `iob_timer` drives the sub-block `iob_timer_core`,
which has its own testbench (`iob_timer_core_tb.v`). In that case, implement
the sub-block for the gate-level simulation of the timer:

```bash
make asic-build CORE=iob_timer_core BUILD_DIR=timer_core
make -C timer_core/hardware/asic sim-run
```

## Configuration

`config.json` is generated during the setup of the build directory and holds the
design name, the Verilog sources, the clock port/period and the target
technology. The following variables, defined in this directory's `Makefile`,
override the generated configuration:

| Variable        | Default value | Description                                       |
| --------------- | ------------- | ------------------------------------------------- |
| `ASIC_PDK`      | `sky130A`     | PDK variant to implement for                      |
| `ASIC_SCL`      | PDK default   | Standard cell library to use                      |
| `CLOCK_PERIOD`  | `10`          | Clock period (ns) of the main clock domain         |
| `ASIC_FLOW`     | `classic`     | LibreLane flow to run                             |
| `ASIC_RUN_TAG`  | core name     | Name of the run directory                         |
| `ASIC_JOBS`     | `4`           | Maximum number of threads/processes used          |
| `ASIC_TB`       | `$(NAME)_tb.v`| Testbench file used in gate-level simulation      |
| `ASIC_EXTRA_FLAGS` |            | Extra configuration overrides of the flow          |

Any other flow variable can be set in the generated configuration, or
overridden on the command line, for example:

```bash
make asic-build ASIC_EXTRA_FLAGS="-c FP_CORE_UTIL=50 -c PL_OPTIMIZE_MIRRORING=1"
```

Some of the values that `py2hwsw` sets by default deviate from the flow's
defaults because of issues observed with the open source PDKs:

| Variable                  | Value | Reason                                                                                  |
| ------------------------- | ----- | ---------------------------------------------------------------------------------------- |
| `MAX_FANOUT_CONSTRAINT`   | `16`  | Without it, the post-layout timing reports max slew violations on the slowest corners     |
| `IO_DELAY_CONSTRAINT`     | `10`  | Percentage of the clock period for the I/O paths. The PDK value (20%) is meant for chip-level I/O pads |
| `FP_CORE_UTIL`            | `40`  | Leaves room for the buffers that the resizer inserts before detailed routing              |
| `PL_OPTIMIZE_MIRRORING`   | `0`   | Mirroring during detailed placement can leave overlaps that the flow cannot legalize     |
| `TIMING_VIOLATION_CORNERS` | `*` | The PDK defaults restrict the timing violation checkers to the typical corners, which hides violations at the slow/fast corners of the post-layout timing |

The frequency reported by `make asic-report` is the one of the *constrained*
clock period, shortened by the worst setup slack of all corners. The intermediate
timing analysis of the flow only reports the typical corners, so the post-layout
signoff timing is the one to trust.

A core or a user can add or override settings by providing an `asic_build.mk`
file in this directory (it is included by the `Makefile`, if it exists), or by
providing a `hardware/asic/asic_setup.py` file in the core's directory (it is
executed at the end of the build directory setup, with the `setup_module`
variable referring to the core object, and can modify `config.json`).
