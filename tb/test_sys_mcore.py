"""cocotb tests for sys_MultiCoreSys (4 cores, private I$, shared banked D$).

isa:   every lab2 assembly test from the course, run on all four cores at
       once with the same values (as Lab 4 section 4.3 suggests), except
       the four in EXCLUDE, which are skipped with the reason.
mcore: tests in the Lab 4 extended syntax, where "< {a,b,c,d}" and
       "> {a,b,c,d}" give each core its own values:
         coreid         each core reports its coreid and numcores CSRs
         add            Figure 13 of the Lab 4 handout
         mem_same_line  each core stores/loads its own word of two shared lines
         loop_spread    16 stores then 16 loads per core, one line apart (all banks)
         loop_conflict  the same, 512 B apart (one bank, one set: dirty evictions)
       each also with random memory and stream delays (_delays).
Per-core cycles and instruction counts are logged.
"""

import random

import cocotb

import course_tests
from lab2_proc.tinyrv2_encoding import assemble
from mcore_harness import NUM_CORES, run_multicore

CASES = {name: (gen, delays) for name, gen, delays in course_tests.collect()}

# Single-core tests that can't pass on 4 cores running the same program
# (Lab 4 section 4.3 says to exclude these). Skipped, not deleted.
EXCLUDE = {
    "csr_core_stats": "checks numcores == 1 and coreid == 0",
    "sw_addr": "cores store different values to the same word over time, so one core can "
               "load another core's store (a race)",
    "sw_random": "same race as sw_addr",
    "sw_delays": "same race as sw_addr",
}


def _register(test_name, func, skip=False):
    func.__name__ = func.__qualname__ = test_name
    globals()[test_name] = cocotb.test(skip=skip)(func)


def per_core(values):
    return "{" + ",".join(f"{v:#x}" for v in values) + "}"


async def run_and_log(dut, asm, delays):
    cycles, insts, stats = await run_multicore(dut, assemble(asm), delays=delays)
    dut._log.info(f"{cycles} cycles, insts per core {insts}, main memory requests {stats}")


def _isa_test(gen, delays):
    async def test(dut):
        random.seed(0xDEADBEEF)  # same as the course conftest: gen_random_test is deterministic
        await run_and_log(dut, gen(), delays)
    return test


#-------------------------------------------------------------------------
# Multicore tests
#-------------------------------------------------------------------------

def gen_coreid():
    return f"""
    csrr x1, coreid
    csrw proc2mngr, x1 > {per_core(range(NUM_CORES))}
    csrr x2, numcores
    csrw proc2mngr, x2 > {NUM_CORES}
    """


def gen_add():
    return """
    csrr x2, mngr2proc < {1,2,3,4}
    csrr x3, mngr2proc < {2,3,4,5}
    add x4, x2, x3
    csrw proc2mngr, x4 > {3,5,7,9}
    """


def gen_mem_same_line():
    # Core c owns word c of the line at 0x2000 (bank 0) and of the line at 0x2010 (bank 1).
    vals0 = [0xA0 + c for c in range(NUM_CORES)]
    vals1 = [0xB0 + c for c in range(NUM_CORES)]
    return f"""
    csrr x1, coreid
    slli x1, x1, 2
    csrr x2, mngr2proc < 0x2000
    add  x3, x2, x1
    csrr x4, mngr2proc < {per_core(vals0)}
    csrr x5, mngr2proc < {per_core(vals1)}
    sw   x4, 0(x3)
    sw   x5, 16(x3)
    lw   x6, 0(x3)
    lw   x7, 16(x3)
    csrw proc2mngr, x6 > {per_core(vals0)}
    csrw proc2mngr, x7 > {per_core(vals1)}
    """


def gen_loop(stride, n=16):
    # Core c writes base_c, base_c+1, ... to its word of n lines, then sums them back.
    bases = [0x100 * c for c in range(NUM_CORES)]
    sums = [n * b + n * (n - 1) // 2 for b in bases]
    return f"""
    csrr x1, coreid
    slli x1, x1, 2
    csrr x2, mngr2proc < 0x2000
    add  x2, x2, x1
    csrr x6, mngr2proc < {per_core(bases)}
    addi x7, x0, {n}
    add  x3, x2, x0
  wloop:
    sw   x6, 0(x3)
    addi x6, x6, 1
    addi x3, x3, {stride}
    addi x7, x7, -1
    bne  x7, x0, wloop
    addi x7, x0, {n}
    add  x3, x2, x0
    addi x8, x0, 0
  rloop:
    lw   x9, 0(x3)
    add  x8, x8, x9
    addi x3, x3, {stride}
    addi x7, x7, -1
    bne  x7, x0, rloop
    csrw proc2mngr, x8 > {per_core(sums)}
    """


MCORE = {
    "coreid": gen_coreid,
    "add": gen_add,
    "mem_same_line": gen_mem_same_line,
    "loop_spread": lambda: gen_loop(16),
    "loop_conflict": lambda: gen_loop(512),
}


def _mcore_test(gen, delays):
    async def test(dut):
        await run_and_log(dut, gen(), delays)
    return test


for _name, _gen in MCORE.items():
    _register(f"mcore_{_name}", _mcore_test(_gen, False))
    _register(f"mcore_{_name}_delays", _mcore_test(_gen, True))

for _name, (_gen, _delays) in CASES.items():
    _register(f"isa_{_name}", _isa_test(_gen, _delays), skip=_name in EXCLUDE)
