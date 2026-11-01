"""Tests for sys_MultiCoreDataCache.

Four cores drive procreq/procresp, one main memory model sits on
mainmemreq/mainmemresp. Like the real cores, each core has at most one
request in flight. Core c only touches words whose word-in-line index is c,
so every cache line holds one word from each core: all four cores contend
for the same banks and lines, yet each core's loads have exactly one
correct answer (a reference memory tracks it).

directed_same_line: each core stores to its word of one line, then loads it back.
directed_evict:     each core fills three lines that map to the same set and bank
                    (2 ways), forcing dirty evictions, then reads all three back.
random_rw:          random loads/stores over 4 KB (4x the total D$ capacity),
                    half of them aimed at a 256 B hot region so there are hits too.
random_rw_delays:   the same with stalls and extra latency on every port.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

from harness import Memory
from mcore_harness import LineMemPort
from net_harness import Sink, Source, run_until

NUM_CORES = 4
BASE = 0x2000
READ, WRITE = 0, 1

REQ_NBITS = 78
RESP_NBITS = 48


# mem_req_4B_t: type[77:74] opaque[73:66] addr[65:34] len[33:32] data[31:0]
def pack_req(type_, addr, data=0):
    return (type_ << 74) | (addr << 34) | data


# mem_resp_4B_t: type[47:44] opaque[43:36] test[35:34] len[33:32] data[31:0]
def unpack_resp(v):
    return dict(type_=(v >> 44) & 0xF, data=v & 0xFFFF_FFFF)


def word_addr(core, k):
    """k-th word owned by core: word index 4k + core, so offset core*4 in its line."""
    return BASE + 4 * (4 * k + core)


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.reset.value = 1
    dut.procreq_val.value = 0
    dut.procreq_msg.value = 0
    dut.procresp_rdy.value = 0
    dut.mainmemreq_rdy.value = 0
    dut.mainmemresp_val.value = 0
    dut.mainmemresp_msg.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.reset.value = 0


async def run_ops(dut, ops, init, delays=False, max_cycles=50000):
    """ops[c] = [(type, addr, data), ...] for core c, issued one at a time.

    init maps addr -> initial word in main memory. Every load is checked
    against a reference memory updated by that core's own earlier stores.
    """
    await reset(dut)

    memory = Memory(size=1 << 16)
    ref = {}
    for addr, word in init.items():
        memory.write(addr, 4, word)
        ref[addr] = word

    # Expected response per op, computed in program order per core (words are disjoint).
    expected = []
    for c in range(NUM_CORES):
        exp = []
        for type_, addr, data in ops[c]:
            if type_ == WRITE:
                ref[addr] = data
                exp.append((WRITE, None))
            else:
                exp.append((READ, ref.get(addr, 0)))
        expected.append(exp)

    stall, latency, gap = (0.4, 4, 3) if delays else (0.0, 0, 0)
    procs = Source(dut.procreq_val, dut.procreq_rdy, dut.procreq_msg, NUM_CORES, max_gap=gap, nbits=REQ_NBITS)
    proc_sink = Sink(dut.procresp_val, dut.procresp_rdy, dut.procresp_msg, NUM_CORES, stall_prob=stall,
                     nbits=RESP_NBITS)
    mainmem = LineMemPort(dut, "mainmem", memory, stall_prob=stall, extra_latency=latency)

    done = [0] * NUM_CORES
    errors = []

    def issue(c):
        type_, addr, data = ops[c][done[c]]
        procs.queues[c].append(pack_req(type_, addr, data))

    def on_resp(c, msg):
        if done[c] >= len(ops[c]):
            errors.append(f"core {c}: extra response {msg:#x}")
            return
        resp = unpack_resp(msg)
        type_, addr, _ = ops[c][done[c]]
        want_type, want_data = expected[c][done[c]]
        if resp["type_"] != want_type:
            errors.append(f"core {c} op {done[c]} ({'lw' if type_ == READ else 'sw'} {addr:#x}): "
                          f"response type {resp['type_']}, expected {want_type}")
        elif want_type == READ and resp["data"] != want_data:
            errors.append(f"core {c} op {done[c]} (lw {addr:#x}): got {resp['data']:#010x}, "
                          f"expected {want_data:#010x}")
        done[c] += 1
        if done[c] < len(ops[c]):
            issue(c)

    proc_sink.on_recv = on_resp
    for c in range(NUM_CORES):
        if ops[c]:
            issue(c)
    for task in (procs, proc_sink, mainmem):
        cocotb.start_soon(task.run(dut.clk))

    def finished():
        return errors or all(done[c] == len(ops[c]) for c in range(NUM_CORES))

    try:
        cycles = await run_until(dut, finished, max_cycles)
    except AssertionError as e:
        raise AssertionError(f"{e}; ops completed per core: {done} of {[len(o) for o in ops]}") from None
    assert not errors, "\n".join(errors[:10])
    dut._log.info(f"{sum(done)} ops in {cycles} cycles, {mainmem.reqs} main memory requests")


@cocotb.test()
async def directed_same_line(dut):
    random.seed(1)
    ops = []
    for c in range(NUM_CORES):
        a = word_addr(c, 0)
        ops.append([(WRITE, a, 0xC0DE_0000 | c), (READ, a, 0)])
    await run_ops(dut, ops, init={})


@cocotb.test()
async def directed_evict(dut):
    # Lines 512 B apart share addr[8:4]: same bank, same set. Three of them overflow a 2-way set.
    random.seed(2)
    ops = []
    for c in range(NUM_CORES):
        addrs = [word_addr(c, 0) + 512 * j for j in range(3)]
        ops.append([(WRITE, a, (c << 28) | (j << 16) | 0xBEEF) for j, a in enumerate(addrs)]
                   + [(READ, a, 0) for a in addrs])
    await run_ops(dut, ops, init={})


def random_ops(num_ops):
    init = {}
    for k in range(256):
        for c in range(NUM_CORES):
            init[word_addr(c, k)] = random.getrandbits(32)
    ops = []
    for c in range(NUM_CORES):
        core_ops = []
        for _ in range(num_ops):
            k = random.randrange(16) if random.random() < 0.5 else random.randrange(256)
            if random.random() < 0.5:
                core_ops.append((WRITE, word_addr(c, k), random.getrandbits(32)))
            else:
                core_ops.append((READ, word_addr(c, k), 0))
        ops.append(core_ops)
    return ops, init


@cocotb.test()
async def random_rw(dut):
    random.seed(0xD5)
    ops, init = random_ops(300)
    await run_ops(dut, ops, init)


@cocotb.test()
async def random_rw_delays(dut):
    random.seed(0xD6)
    ops, init = random_ops(300)
    await run_ops(dut, ops, init, delays=True)
