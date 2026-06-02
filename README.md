# JNLCFD

JNLCFD is a small experimental CFD and meshing environment built around a C
numerical core and an embedded Lua scripting layer. The goal is to make CFD
studies reproducible, auditable, and composable: a simulation is written as a
script that defines geometry, mesh generation, physics, boundary conditions,
solver algorithm, post-processing, sweeps, and plots in one place.

The showcase scripts in `showcase/` reproduce the validation and design-study
figures used in the accompanying report.

## Dependencies

JNLCFD currently expects a Unix-like development environment with:

- `gcc`
- `make`
- `cmake`
- `pkg-config`
- `lua5.5` development package, visible through `pkg-config --cflags lua5.5` and `pkg-config --libs lua5.5`
- `raylib`
- `readline`
- `libm`
- `objcopy`, usually provided by GNU binutils
- Git submodules:
  - `vendor/Triangle`
  - `vendor/fennel`

The build system compiles the C core, command-line entry points, the vendored
Triangle libraries, and the vendored Fennel runtime. The relevant build rules
are in `makefile`.

On a Debian/Ubuntu-like system, the package names are likely to be similar to:

```sh
sudo apt install build-essential cmake pkg-config binutils libreadline-dev libraylib-dev
```

The exact Lua package name depends on the distribution. You need a Lua 5.5
package that provides `pkg-config` metadata under the name `lua5.5`.

## Building

Clone the repository with submodules, or initialise them after cloning:

```sh
git submodule init
git submodule update
```

Build the release binaries:

```sh
make release
```

This creates binaries under:

```text
bin/release/
```

The main interactive entry point used for the showcase studies is:

```sh
bin/release/cli
```

For a debug build:

```sh
make debug
```

To run the C unit tests:

```sh
make test
```

To clean generated build artefacts:

```sh
make clean
```

For verbose build commands:

```sh
make release V=1
```

## Running a showcase study

Each showcase script is a Lua file that loads into an interactive JNLCFD REPL. For example:

```sh
bin/release/cli showcase/poiseuille.lua
```

Inside the REPL, type:

```fennel
,usage
```

to see the available commands for that study.

Most studies support:

```fennel
(run)
(plot-comparison)
(write-comparison "path/to/output.csv")
(write-comparison "path/to/output.pdf")
(write-comparison "path/to/output.png")
```

The plotting/writing helpers are generated from the same figure definition. The
output file extension selects the output format. For example, writing to `.csv`
exports the plotted data, while writing to `.pdf` or `.png` exports the figure.

## Reproducing the validation figures

The validation cases are in:

```text
showcase/couette.lua
showcase/poiseuille.lua
showcase/ghia_cavity.lua
```

Create output directories first:

```sh
mkdir -p showcase/out/couette
mkdir -p showcase/out/poiseuille
mkdir -p showcase/out/ghia_ldc
```

### Couette flow

Run:

```sh
bin/release/cli showcase/couette.lua
```

Inside the REPL:

```fennel
(write-comparison "showcase/out/couette/couette_comparison.csv")
(write-comparison "showcase/out/couette/couette_comparison.pdf")
(write-comparison "showcase/out/couette/couette_comparison.png")
```

This compares the numerical velocity profile with the analytical linear Couette
solution.

### Poiseuille flow

Run:

```sh
bin/release/cli showcase/poiseuille.lua
```

Inside the REPL:

```fennel
(write-comparison "showcase/out/poiseuille/poiseuille_comparison.csv")
(write-comparison "showcase/out/poiseuille/poiseuille_comparison.pdf")
(write-comparison "showcase/out/poiseuille/poiseuille_comparison.png")
```

This compares the fully developed outlet velocity profile with the analytical
parabolic Poiseuille solution.

### Ghia lid-driven cavity: low-Re CDS sweeps

Run:

```sh
bin/release/cli showcase/ghia_cavity.lua
```

Inside the REPL:

```fennel
(write-u-sweep "showcase/out/ghia_ldc/ghia_u_sweep.csv")
(write-u-sweep "showcase/out/ghia_ldc/ghia_u_sweep.pdf")
(write-u-sweep "showcase/out/ghia_ldc/ghia_u_sweep.png")

(write-v-sweep "showcase/out/ghia_ldc/ghia_v_sweep.csv")
(write-v-sweep "showcase/out/ghia_ldc/ghia_v_sweep.pdf")
(write-v-sweep "showcase/out/ghia_ldc/ghia_v_sweep.png")
```

These figures compare centreline velocity profiles against the Ghia et al.
reference data for the low-Reynolds-number CDS validation sweep.

### Ghia lid-driven cavity: Re = 7500, UDS

Run:

```sh
bin/release/cli showcase/ghia_cavity.lua
```

Inside the REPL:

```fennel
(local r (run {:Re 7500 :scheme "uds"}))

(write-u-comparison "showcase/out/ghia_ldc/ghia_u_comparison_Re7500UDS.csv" r)
(write-u-comparison "showcase/out/ghia_ldc/ghia_u_comparison_Re7500UDS.pdf" r)
(write-u-comparison "showcase/out/ghia_ldc/ghia_u_comparison_Re7500UDS.png" r)

(write-v-comparison "showcase/out/ghia_ldc/ghia_v_comparison_Re7500UDS.csv" r)
(write-v-comparison "showcase/out/ghia_ldc/ghia_v_comparison_Re7500UDS.pdf" r)
(write-v-comparison "showcase/out/ghia_ldc/ghia_v_comparison_Re7500UDS.png" r)
```

This reproduces the high-Reynolds-number UDS comparison case.

## Reproducing the channel-fin design-study figures

The channel-fin study is in:

```text
showcase/channel_fin_heat.lua
```

Create its output directory:

```sh
mkdir -p showcase/out/channel_fin
```

Run:

```sh
bin/release/cli showcase/channel_fin_heat.lua
```

Inside the REPL, use `,usage` to check the exact generated command names. The
expected workflow is:

```fennel
(run)
```

to run the default case.

### Height sweep: heat removed

```fennel
(write-height-heat "showcase/out/channel_fin/fin_height_heat.csv")
(write-height-heat "showcase/out/channel_fin/fin_height_heat.pdf")
(write-height-heat "showcase/out/channel_fin/fin_height_heat.png")
```

### Height sweep: pressure drop

```fennel
(write-height-pressure "showcase/out/channel_fin/fin_height_pressure.csv")
(write-height-pressure "showcase/out/channel_fin/fin_height_pressure.pdf")
(write-height-pressure "showcase/out/channel_fin/fin_height_pressure.png")
```

### Pareto heat-pressure trade-off

```fennel
(write-pareto "showcase/out/channel_fin/channel_fin_pareto.csv")
(write-pareto "showcase/out/channel_fin/channel_fin_pareto.pdf")
(write-pareto "showcase/out/channel_fin/channel_fin_pareto.png")
```

### VTK output for ParaView

To write the default simulation result as VTK:

```fennel
(write-vtk "showcase/out/channel_fin/channel_fin_default.vtk")
```

Or explicitly keep a result and write it:

```fennel
(local r (run))
(write-vtk "showcase/out/channel_fin/channel_fin_default.vtk" r)
```

The VTK file can be opened in ParaView:

```sh
paraview showcase/out/channel_fin/channel_fin_default.vtk
```

Useful fields include velocity components, pressure, temperature, and the
velocity vector if written by the study.

## Guided tour of the codebase

The repository is split into a small C core, Lua orchestration libraries, and
showcase scripts.

1. `include/` and `src/`  
   These contain the C numerical core. Start with:
   - `include/mesh2d.h` and `src/mesh2d/` for the mesh data structures and structured/triangular mesh support.
   - `include/fvm/operators.h` and `src/fvm/operators.c` for finite-volume matrix assembly operators.
   - `include/fvm/bc.h` and `src/fvm/bc.c` for boundary-condition application.
   - `include/fvm/linalg.h` and `src/fvm/linalg.c` for sparse linear algebra.
   - `include/vec.h` and `src/vec.c` for the core numeric vector storage.

2. `src/*_lua.c`  
   These files bind the C core into Lua. They are the bridge between the
   high-performance numerical routines and the scripting layer. Good first
   files are:
   - `src/mesh2d/mesh2d_lua.c`
   - `src/fvm/fvm_lua.c`
   - `src/geo2d_lua.c`
   - `src/vec_lua.c`

3. `lua/jnl/core/`  
   This is the symbolic layer used to describe equations and dependencies. It
   contains expression and registry machinery used by the equation compiler.

4. `lua/jnl/fvm/`  
   This is the high-level finite-volume Lua API. It contains the Study helper,
   canned solver setups, equation/operator wrappers, boundary-condition
   helpers, and VTK/plotting integrations. The file `lua/jnl/fvm/study.lua` is
   the main FVM-specific study wrapper.

5. `lua/jnl/repl/`  
   This provides the interactive study interface. The generic Study helper
   registers commands such as `(run)`, `(plot-comparison)`, `(write-comparison
   "out.csv")`, sweeps, outputs, and generated usage text. This is the layer
   that turns a Lua script into a reproducible interactive CFD study.

6. `showcase/`  
   These are the most useful files for understanding how the pieces fit together. Start with:
   - `showcase/couette.lua`
   - `showcase/poiseuille.lua`
   - `showcase/ghia_cavity.lua`
   - `showcase/channel_fin_heat.lua`

   These scripts show the intended user-facing style: define design variables
   and defaults, register mesh/physics/algorithm/BC builders, define one
   `evaluate` path, then register figures, sweeps, optimisation studies, or VTK
   writers.

## Repository layout

A shortened top-level layout is:

```text
bin/                 built executables
cmd/                 C entry points for CLI/UI/examples
include/             public C headers
src/                 C implementation and Lua bindings
lua/                 Lua/Fennel-facing library code
showcase/            reproducible study scripts
test/                C unit tests
makefile             build rules
README.md            this file
```

The main release executable used for reproducing showcase results is:

```text
bin/release/cli
```

## Notes on reproducibility

The central reproducibility idea is that each result is generated from a
version-controlled script, rather than from an opaque saved solver state. The
script contains the procedure: geometry, mesh, equations, boundary conditions,
solver algorithm, post-processing, sweeps, and figures.

The REPL interface is intended to make this procedure inspectable. For example,
inside a study you can use:

```fennel
,usage
(inspect-registry)
(inspect-algorithm)
(inspect-instructions)
(default-design)
(defaults)
```

where available, to inspect the simulation setup before or after running it.
