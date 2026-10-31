#!/usr/bin/env python3
"""Builds a design with Verilator and runs its cocotb tests.

  python tb/run.py isa                    # all 214 course tests on ProcAlt
  python tb/run.py isa --impl bht         # same tests on the ProcBHT working copy
  python tb/run.py isa -k 'add_.*'        # only tests whose name matches
  python tb/run.py ubmark --impl bht      # microbenchmarks + CPI table
  python tb/run.py ubmark --mem-delays    # with random memory stalls
  python tb/run.py isa -k add_basic --waves   # dump build/<impl>/dump.fst
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

# The course code is lint-clean under the course's Verilator flags, not -Wall.
VERILATOR_ARGS = ["-Wno-fatal", "-Wno-lint", "-Wno-style", "-Wno-TIMESCALEMOD", "-Wno-MULTIDRIVEN"]


def build_and_test(source, top, build_dir, test_module, test_filter=None, waves=False, extra_env=None):
    runner = get_runner("verilator")
    runner.build(
        sources=[source],
        includes=[RTL, LABS],
        hdl_toplevel=top,
        build_args=VERILATOR_ARGS + (["--trace-fst", "--trace-structs"] if waves else []),
        build_dir=build_dir,
        waves=waves,
        timescale=("1ns", "1ps"),
    )
    results_xml = runner.test(
        test_module=test_module,
        hdl_toplevel=top,
        test_dir=ROOT / "tb",
        build_dir=build_dir,
        test_filter=test_filter,
        waves=waves,
        extra_env={"PYTHONPATH": os.pathsep.join([str(ROOT / "tb"), str(LABS)]), **(extra_env or {})},
    )
    return get_results(results_xml)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("suite", choices=["isa", "ubmark"])
    p.add_argument("--impl", choices=list(PROCS), default="alt")
    p.add_argument("-k", "--filter", help="regex on the test case name, e.g. 'mul_.*'")
    p.add_argument("--mem-delays", action="store_true", help="ubmark: random memory stalls + 3 extra cycles")
    p.add_argument("--waves", action="store_true", help="dump an FST waveform")
    args = p.parse_args()

    source, top = PROCS[args.impl]
    results_file = ROOT / "build" / f"ubmark-{args.impl}{'-delays' if args.mem_delays else ''}.json"
    if args.suite == "ubmark" and results_file.exists():
        results_file.unlink()

    num_tests, num_failed = build_and_test(
        source, top, ROOT / "build" / args.impl, "test_proc",
        test_filter=rf"{args.suite}/\w+=({args.filter or '.*'})$",
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
