"""cocotb harness for the multicore system (sys_MultiCoreSys).

Plays the role of the course's Lab 4 MultiCoreSys test harness: four
mngr2proc sources, four proc2mngr sinks, and a two-port main memory that
speaks 16B cache-line messages (port 0 = D$ via dmemreq/dmemresp, port 1 =
I$ via imemreq/imemresp), both backed by one flat Memory.

Programs come from the course assembler. A single-core test (sections
.mngr2proc/.proc2mngr) runs on all four cores with the same values; a test
written in the Lab 4 extended syntax ("< {1,2,3,4}", sections
.mngr2proc_<i>/.proc2mngr_<i>) gives each core its own values.
"""

import random
import struct
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge

from harness import Memory
from net_harness import Sink, Source

NUM_CORES = 4
MEM_REQ_READ = 0
MEM_REQ_WRITE = 1


# mem_req_16B_t: type[175:172] opaque[171:164] addr[163:132] len[131:128] data[127:0]
def unpack_req16(v):
    return dict(type_=(v >> 172) & 0xF, opaque=(v >> 164) & 0xFF, addr=(v >> 132) & 0xFFFF_FFFF,
                len=(v >> 128) & 0xF, data=v & ((1 << 128) - 1))


# mem_resp_16B_t: type[145:142] opaque[141:134] test[133:132] len[131:128] data[127:0]
def pack_resp16(type_, opaque, len_, data):
    return (type_ << 142) | (opaque << 134) | (len_ << 128) | data


class LineMemPort:
    """One 16B val/rdy port onto a Memory: signals <prefix>req_* and <prefix>resp_*.

    stall_prob: chance each cycle that the port refuses a request.
    extra_latency: cycles added before a response becomes valid.
    """

    def __init__(self, dut, prefix, memory, stall_prob=0.0, extra_latency=0, depth=2):
        self.req_msg = getattr(dut, f"{prefix}req_msg")
        self.req_val = getattr(dut, f"{prefix}req_val")
        self.req_rdy = getattr(dut, f"{prefix}req_rdy")
        self.resp_msg = getattr(dut, f"{prefix}resp_msg")
        self.resp_val = getattr(dut, f"{prefix}resp_val")
        self.resp_rdy = getattr(dut, f"{prefix}resp_rdy")
        self.memory = memory
        self.stall_prob, self.extra_latency, self.depth = stall_prob, extra_latency, depth
        self.pending = deque()  # [ready_cycle, resp_bits]
        self.cycle = 0
        self.reqs = 0

    def reset_outputs(self):
        self.req_rdy.value = 0
        self.resp_val.value = 0
        self.resp_msg.value = 0

    def access(self, req):
        nbytes = req["len"] or 16
        if req["type_"] == MEM_REQ_READ:
            data = self.memory.read(req["addr"], nbytes)
        elif req["type_"] == MEM_REQ_WRITE:
            self.memory.write(req["addr"], nbytes, req["data"])
            data = 0
        else:
            raise AssertionError(f"unexpected main memory request type {req['type_']}")
        return pack_resp16(req["type_"], req["opaque"], req["len"], data)

    async def run(self, clk):
        while True:
            await FallingEdge(clk)
            accept = len(self.pending) < self.depth and random.random() >= self.stall_prob
            self.req_rdy.value = int(accept)
            head_ready = bool(self.pending) and self.pending[0][0] <= self.cycle
            self.resp_val.value = int(head_ready)
            self.resp_msg.value = self.pending[0][1] if head_ready else 0

            await ReadOnly()
            req_fire = accept and self.req_val.value == 1
            req = unpack_req16(int(self.req_msg.value)) if req_fire else None
            resp_fire = head_ready and self.resp_rdy.value == 1

            await RisingEdge(clk)
            self.cycle += 1
            if resp_fire:
                self.pending.popleft()
            if req_fire:
                self.reqs += 1
                self.pending.append([self.cycle + self.extra_latency, self.access(req)])


def _words(data):
    return [w for (w,) in struct.iter_unpack("<I", data)]


def split_image(mem_image):
    """Returns (memory, src[core], sink[core]) from a SparseMemoryImage."""
    memory = Memory()
    src = [[] for _ in range(NUM_CORES)]
    sink = [[] for _ in range(NUM_CORES)]
    for section in mem_image.get_sections():
        name = section.name
        if name == ".mngr2proc":
            for c in range(NUM_CORES):
                src[c] += _words(section.data)
        elif name == ".proc2mngr":
            for c in range(NUM_CORES):
                sink[c] += _words(section.data)
        elif name.startswith(".mngr2proc_"):
            src[int(name.rsplit("_", 1)[1])] += _words(section.data)
        elif name.startswith(".proc2mngr_"):
            sink[int(name.rsplit("_", 1)[1])] += _words(section.data)
        else:
            memory.load_section(section.addr, section.data)
    return memory, src, sink


async def run_multicore(dut, mem_image, delays=False, max_cycles=50000, seed=0xDEADBEEF):
    """Runs one program on all four cores until every source and sink is done.

    Returns (num_cycles, insts[core], stats) where stats counts main memory
    requests per port. num_cycles counts from the end of reset.
    """
    random.seed(seed)
    clk = dut.clk
    cocotb.start_soon(Clock(clk, 10, unit="ns").start())

    memory, src_msgs, sink_msgs = split_image(mem_image)

    stall_prob, extra_latency, max_gap = (0.5, 3, 20) if delays else (0.0, 0, 0)
    dmem = LineMemPort(dut, "dmem", memory, stall_prob, extra_latency)
    imem = LineMemPort(dut, "imem", memory, stall_prob, extra_latency)
    src = Source(dut.mngr2proc_val, dut.mngr2proc_rdy, dut.mngr2proc_msg, NUM_CORES, max_gap=max_gap, nbits=32)
    sink = Sink(dut.proc2mngr_val, dut.proc2mngr_rdy, dut.proc2mngr_msg, NUM_CORES,
                stall_prob=0.3 if delays else 0.0, nbits=32)
    for c in range(NUM_CORES):
        src.queues[c].extend(src_msgs[c])
    expected = [deque(msgs) for msgs in sink_msgs]

    cycle = 0
    errors = []

    def on_recv(c, got):
        if not expected[c]:
            errors.append(f"cycle {cycle}: core {c} sent unexpected proc2mngr 0x{got:08x}")
            return
        want = expected[c].popleft()
        if got != want:
            errors.append(f"cycle {cycle}: core {c} proc2mngr got 0x{got:08x}, expected 0x{want:08x}")

    sink.on_recv = on_recv

    dut.mngr2proc_val.value = 0
    dut.mngr2proc_msg.value = 0
    dut.proc2mngr_rdy.value = 0
    dmem.reset_outputs()
    imem.reset_outputs()
    dut.reset.value = 1
    for _ in range(3):
        await RisingEdge(clk)
    await FallingEdge(clk)
    dut.reset.value = 0

    for component in (dmem, imem, src, sink):
        cocotb.start_soon(component.run(clk))

    insts = [0] * NUM_CORES
    while not (src.done() and all(not e for e in expected)):
        assert not errors, "\n".join(errors[:10])
        if cycle >= max_cycles:
            left = [len(e) for e in expected]
            raise AssertionError(f"timed out after {max_cycles} cycles; proc2mngr messages still "
                                 f"expected per core: {left}")
        await ReadOnly()
        commit = int(dut.commit_inst.value)
        for c in range(NUM_CORES):
            insts[c] += (commit >> c) & 1
        await RisingEdge(clk)
        cycle += 1
    assert not errors, "\n".join(errors[:10])

    return cycle, insts, {"dmem_reqs": dmem.reqs, "imem_reqs": imem.reqs}
