#!/usr/bin/env python3
"""Builds a design with Verilator and runs its cocotb tests.

  python tb/run.py isa                    # all 214 course tests on ProcAlt
  python tb/run.py isa --impl bht         # same tests on the ProcBHT working copy
  python tb/run.py isa -k 'add_.*'        # only tests whose name matches
  python tb/run.py ubmark --impl bht      # microbenchmarks + CPI table
  python tb/run.py ubmark --mem-delays    # with random memory stalls
  python tb/run.py isa -k add_basic --waves   # dump build/<impl>/dump.fst
  python tb/run.py route                  # mesh route unit, all 16 cases
  python tb/run.py router                 # one mesh router, random traffic
  python tb/run.py mesh                   # 2x2 mesh: random traffic + latency sweep
  python tb/run.py cachenet               # CacheNet: 4 procs <-> 4 banks over two meshes
  python tb/run.py mcdcache               # MultiCoreDataCache: 4 cores, banks, main memory
  python tb/run.py mcore                  # MultiCoreSys: mcore tests + all ISA tests on 4 cores
  python tb/run.py mcore -k 'mcore_.*'    # only the multicore-specific tests
"""

import argparse
import json
import os
import sys
from pathlib import Path

from cocotb_tools.runner import get_results, get_runner

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "rtl"
# ECE 4750 lab code (vc/, lab1_imul/, lab2_proc/, lab3_mem/) lives in the
# workspace folder next to this repo and is not committed.
LABS = ROOT.parent / "labs"

# Processor implementations: (source file, top module)
PROCS = {
    "base": (LABS / "lab2_proc/ProcBase.v", "lab2_proc_ProcBase"),
    "alt": (LABS / "lab2_proc/ProcAlt.v", "lab2_proc_ProcAlt"),
    "bht": (RTL / "proc/ProcBHT.v", "proc_ProcBHT"),
}

# Network suites: (source file, top module, cocotb test module)
NET = {
    "route": (RTL / "net/MeshRouteUnit.v", "net_MeshRouteUnit", "test_net_route"),
    "router": (RTL / "net/MeshRouter.v", "net_MeshRouter", "test_net_router"),
    "mesh": (RTL / "net/Mesh.v", "net_Mesh", "test_net_mesh"),
    "cachenet": (RTL / "sys/CacheNet.v", "sys_CacheNet", "test_sys_cachenet"),
    "mcdcache": (RTL / "sys/MultiCoreDataCache.v", "sys_MultiCoreDataCache", "test_sys_mcdcache"),
    "mcore": (RTL / "sys/MultiCoreSys.v", "sys_MultiCoreSys", "test_sys_mcore"),
}

# The course code is lint-clean under the course's Verilator flags, not -Wall.
VERILATOR_ARGS = ["-Wno-fatal", "-Wno-lint", "-Wno-style", "-Wno-TIMESCALEMOD", "-Wno-MULTIDRIVEN"]


def build_and_test(source, top, build_dir, test_module, test_filter=None, waves=False, extra_env=None,
                   extra_includes=()):
    # Verilator's makefile calls `python3`; make it the venv's so it matches the runner's PYTHONPATH.
    venv_bin = str(Path(sys.executable).parent)
    if not os.environ["PATH"].startswith(venv_bin):
        os.environ["PATH"] = venv_bin + os.pathsep + os.environ["PATH"]
    runner = get_runner("verilator")
    runner.build(
        sources=[source],
        includes=[*extra_includes, RTL, LABS],
        hdl_toplevel=top,
        build_args=VERILATOR_ARGS + (["--trace-fst", "--trace-structs"] if waves else []),
        build_dir=build_dir,
        waves=waves,
        timescale=("1ns", "1ps"),
    )
    # The runner hands its own sys.path to the simulator as PYTHONPATH.
    for path in (str(ROOT / "tb"), str(LABS)):
        if path not in sys.path:
            sys.path.insert(0, path)
    results_xml = runner.test(
        test_module=test_module,
        hdl_toplevel=top,
        test_dir=ROOT / "tb",
        build_dir=build_dir,
        test_filter=test_filter,
        waves=waves,
        extra_env=extra_env or {},
    )
    return get_results(results_xml)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("suite", choices=["isa", "ubmark", *NET])
    p.add_argument("--impl", choices=list(PROCS), default="alt")
    p.add_argument("-k", "--filter", help="regex on the test case name, e.g. 'mul_.*'")
    p.add_argument("--mem-delays", action="store_true", help="ubmark: random memory stalls + 3 extra cycles")
    p.add_argument("--waves", action="store_true", help="dump an FST waveform")
    args = p.parse_args()

    if args.suite in NET:
        source, top, module = NET[args.suite]
        results_file = ROOT / "build" / f"net-{args.suite}.json"
        num_tests, num_failed = build_and_test(
            source, top, ROOT / "build" / f"net-{args.suite}", module,
            test_filter=args.filter, waves=args.waves,
            extra_env={"RESULTS_FILE": str(results_file)},
        )
        if args.suite == "mesh" and results_file.exists():
            print(f"\n{'injection':>10}{'latency':>10}{'throughput':>12}")
            for r in json.loads(results_file.read_text()):
                print(f"{r['rate']:>10.2f}{r['avg_latency']:>10.2f}{r['throughput']:>12.3f}")
        print(f"\n{num_tests - num_failed}/{num_tests} passed")
        return 1 if num_failed or num_tests == 0 else 0

    source, top = PROCS[args.impl]
    results_file = ROOT / "build" / f"ubmark-{args.impl}{'-delays' if args.mem_delays else ''}.json"
    if args.suite == "ubmark" and results_file.exists():
        results_file.unlink()

    num_tests, num_failed = build_and_test(
        source, top, ROOT / "build" / args.impl, "test_proc",
        test_filter=rf"\.{args.suite}_({args.filter or '.*'})$",
        waves=args.waves,
        extra_env={"RESULTS_FILE": str(results_file), "MEM_DELAYS": "1" if args.mem_delays else "0"},
    )

    if args.suite == "ubmark" and results_file.exists():
        results = json.loads(results_file.read_text())
        print(f"\n{'ubmark':<14}{'cycles':>8}{'insts':>8}{'CPI':>7}   ({args.impl})")
        for name, r in results.items():
            print(f"{name:<14}{r['cycles']:>8}{r['insts']:>8}{r['cpi']:>7.2f}")

    print(f"\n{num_tests - num_failed}/{num_tests} passed")
    return 1 if num_failed or num_tests == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
