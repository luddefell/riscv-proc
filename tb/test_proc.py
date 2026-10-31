"""cocotb tests for a TinyRV2 processor (ProcBase or ProcAlt).

isa:    every lab2 assembly test from the course, same names as the course.
ubmark: the lab2 microbenchmarks, verified against their reference output,
        with cycles / instructions / CPI written to $RESULTS_FILE.
"""

import json
import os

import cocotb

import course_tests
from harness import run_program
from lab2_proc.tinyrv2_encoding import assemble
from lab2_proc.ubmark.proc_ubmark_bsearch import ubmark_bsearch
from lab2_proc.ubmark.proc_ubmark_cmult import ubmark_cmult
from lab2_proc.ubmark.proc_ubmark_mfilt import ubmark_mfilt
from lab2_proc.ubmark.proc_ubmark_vvadd_opt import ubmark_vvadd_opt
from lab2_proc.ubmark.proc_ubmark_vvadd_unopt import ubmark_vvadd_unopt

CASES = {name: (gen, delays) for name, gen, delays in course_tests.collect()}

UBMARKS = {
    "vvadd-unopt": ubmark_vvadd_unopt,
    "vvadd-opt": ubmark_vvadd_opt,
    "cmult": ubmark_cmult,
    "mfilt": ubmark_mfilt,
    "bsearch": ubmark_bsearch,
}


@cocotb.test()
@cocotb.parametrize(case=list(CASES))
async def isa(dut, case):
    gen, delays = CASES[case]
    await run_program(dut, assemble(gen()), delays=delays)


@cocotb.test()
@cocotb.parametrize(name=list(UBMARKS))
async def ubmark(dut, name):
    bench = UBMARKS[name]
    mem_delays = os.environ.get("MEM_DELAYS") == "1"
    cycles, insts, memory = await run_program(dut, bench.gen_mem_image(), delays=mem_delays)
    assert bench.verify(memory.data), f"{name}: output does not match the reference"

    cpi = cycles / insts
    dut._log.info(f"{name}: num_cycles={cycles} num_insts={insts} CPI={cpi:.2f}")
    results_file = os.environ.get("RESULTS_FILE")
    if results_file:
        results = {}
        if os.path.exists(results_file):
            with open(results_file) as f:
                results = json.load(f)
        results[name] = {"cycles": cycles, "insts": insts, "cpi": round(cpi, 3)}
        with open(results_file, "w") as f:
            json.dump(results, f, indent=2)
