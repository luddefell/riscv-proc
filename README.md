# riscv-proc - an extension of ECE 4750
Delving deeper into comp arch one step at a time, fu avneb 2eqha yh4r y.

## Current BHT implementation
### Dpath Illustration
<p align="center">
  <img src="docs/proc-bht-dpath.png" alt="5-stage pipeline datapath with BHT" width="650">
</p>

### Design decisions
- starts in strictly not taken
- wired into dpath partially (would probably not do that in future)
- used AI for plumbing, it also made the drop unit a counter and the fetch queue 4 deep, to survive a mispredicted predicted-taken branch. (wierd bug idrk)
### Notes
- study up on ctrl logic changes

## 2D mesh NoC
### Mesh illustration
<p align="center">
  <img src="docs/mesh-3x3.jpg" alt="3x3 mesh of routers with N/S/E/W channels and local terminals" width="400">
</p>

### Design decisions
- XY routing (no deadlocking)
- 2x2 mesh (the picture was made prior to multicore planning)
- round robin arbitration (see MeshSwitchUnit.v)
- Used AI for plumbing, learning, and intial cocotb tests
### Notes
- study up on Mesh.v and the Router

## Multicore system
### System
<p align="center">
  <img src="docs/multicore-sys.png" alt="4 cores, private I-caches, shared banked D-cache, MemNet to test memory" width="650">
</p>

### CacheNet: core 2 `lw 0x2010` → bank 1
<p align="center">
  <img src="docs/cachenet-lw-trace.png" alt="CacheNet trace: request core 2 to bank 1, response bank 1 to core 2" width="550">
</p>

### Design decisions
- 4 cores
- stateless adapters (also only one design)
- same network for both (cache and memroy traffic)
- AI was used for plumbing, learning, intial testing


## Future Steps
- Full RISC-V compliance
- PyUVM verification
- Synthesis on Cyclone V
- C benchmarking
- Novel additions
  - Measuring, in real RTL, what each x86-compatibility assist costs RISC-V.
- A compiler???
- contribute to the open-source
