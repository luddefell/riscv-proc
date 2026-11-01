# riscv-proc
Delving deeper into comp arch one step at a time.

## Current BHT implementation
### Drawing
![5-stage pipeline datapath with BHT](docs/proc-bht-dpath.png)
### Design decisions
- starts in strictly not taken
- wired into dpath partially (would probably not do that in future)
- used AI for plumbing, it also made the drop unit a counter and the fetch queue 4 deep, to survive a mispredicted predicted-taken branch. (wierd bug idrk)
