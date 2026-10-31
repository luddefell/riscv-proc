"""cocotb test harness for the TinyRV2 processors in labs/lab2_proc.

Plays the role of the course's PyMTL TestHarness: a two-port test memory
(imem + dmem), a mngr2proc source and a proc2mngr sink, all speaking the
val/rdy protocol. Every component drives its outputs on the falling edge,
samples handshakes in ReadOnly just before the rising edge, and updates its
own state after the rising edge, so a transfer happens exactly when val and
rdy are both high at a rising edge.
"""

import random
import struct
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge

MEM_REQ_READ = 0
MEM_REQ_WRITE = 1
MEM_REQ_WRITE_INIT = 2


def bits(value, lsb, width):
    return (value >> lsb) & ((1 << width) - 1)


# mem_req_4B_t (78 bits): type[77:74] opaque[73:66] addr[65:34] len[33:32] data[31:0]
def unpack_mem_req(v):
    return dict(type_=bits(v, 74, 4), opaque=bits(v, 66, 8), addr=bits(v, 34, 32),
                len=bits(v, 32, 2), data=bits(v, 0, 32))


# mem_resp_4B_t (48 bits): type[47:44] opaque[43:36] test[35:34] len[33:32] data[31:0]
def pack_mem_resp(type_, opaque, len_, data):
    return (type_ << 44) | (opaque << 36) | (len_ << 32) | (data & 0xFFFF_FFFF)


class Memory:
    """Flat byte-addressed memory shared by all ports."""

    def __init__(self, size=1 << 20):
        self.data = bytearray(size)

    def load_section(self, addr, payload):
        self.data[addr:addr + len(payload)] = payload

    def read(self, addr, nbytes):
        return int.from_bytes(self.data[addr:addr + nbytes], "little")

    def write(self, addr, nbytes, value):
        self.data[addr:addr + nbytes] = (value & ((1 << (8 * nbytes)) - 1)).to_bytes(nbytes, "little")

    def access(self, req):
        nbytes = req["len"] or 4
        if req["type_"] == MEM_REQ_READ:
            data = self.read(req["addr"], nbytes)
        elif req["type_"] in (MEM_REQ_WRITE, MEM_REQ_WRITE_INIT):
            self.write(req["addr"], nbytes, req["data"])
            data = 0
        else:
            raise AssertionError(f"unsupported memory request type {req['type_']}")
        return pack_mem_resp(req["type_"], req["opaque"], req["len"], data)


class MemPort:
    """One val/rdy request/response port onto a Memory.

    stall_prob: chance each cycle that the port refuses a request.
    extra_latency: cycles added before a response becomes valid.
    """

    def __init__(self, dut, prefix, memory, clock_count, stall_prob=0.0, extra_latency=0, depth=2):
        self.req_msg = getattr(dut, f"{prefix}_reqstream_msg")
        self.req_val = getattr(dut, f"{prefix}_reqstream_val")
        self.req_rdy = getattr(dut, f"{prefix}_reqstream_rdy")
        self.resp_msg = getattr(dut, f"{prefix}_respstream_msg")
        self.resp_val = getattr(dut, f"{prefix}_respstream_val")
        self.resp_rdy = getattr(dut, f"{prefix}_respstream_rdy")
        self.memory = memory
        self.cycle = clock_count
        self.stall_prob = stall_prob
        self.extra_latency = extra_latency
        self.depth = depth
        self.pending = deque()  # (ready_cycle, resp_bits)

    def reset_outputs(self):
        self.req_rdy.value = 0
        self.resp_val.value = 0
        self.resp_msg.value = 0

    async def run(self, clk):
        while True:
            await FallingEdge(clk)
            accept = len(self.pending) < self.depth and random.random() >= self.stall_prob
            self.req_rdy.value = int(accept)
            head_ready = bool(self.pending) and self.pending[0][0] <= self.cycle()
            self.resp_val.value = int(head_ready)
            self.resp_msg.value = self.pending[0][1] if head_ready else 0

            await ReadOnly()
            req_fire = accept and self.req_val.value == 1
            req = unpack_mem_req(int(self.req_msg.value)) if req_fire else None
            resp_fire = head_ready and self.resp_rdy.value == 1

            await RisingEdge(clk)
            if resp_fire:
                self.pending.popleft()
            if req_fire:
                self.pending.append((self.cycle() + self.extra_latency, self.memory.access(req)))


class StreamSource:
    """Sends a list of 32-bit messages, optionally with random gaps."""

    def __init__(self, val, rdy, msg, msgs, max_gap=0):
        self.val, self.rdy, self.msg = val, rdy, msg
        self.msgs = deque(msgs)
        self.max_gap = max_gap
        self.gap = 0

    def done(self):
        return not self.msgs

    async def run(self, clk):
        while True:
            await FallingEdge(clk)
            send = bool(self.msgs) and self.gap == 0
            self.val.value = int(send)
            self.msg.value = self.msgs[0] if send else 0

            await ReadOnly()
            fire = send and self.rdy.value == 1

            await RisingEdge(clk)
            if self.gap:
                self.gap -= 1
            if fire:
                self.msgs.popleft()
                self.gap = random.randint(0, self.max_gap)


class StreamSink:
    """Checks received 32-bit messages against an expected list, in order."""

    def __init__(self, val, rdy, msg, expected, cycle, max_gap=0):
        self.val, self.rdy, self.msg = val, rdy, msg
        self.expected = deque(expected)
        self.cycle = cycle
        self.max_gap = max_gap
        self.gap = 0

    def done(self):
        return not self.expected

    async def run(self, clk):
        while True:
            await FallingEdge(clk)
            ready = self.gap == 0
            self.rdy.value = int(ready)

            await ReadOnly()
            fire = ready and self.val.value == 1
            got = int(self.msg.value) if fire else None

            await RisingEdge(clk)
            if self.gap:
                self.gap -= 1
            if fire:
                assert self.expected, f"cycle {self.cycle()}: unexpected proc2mngr message 0x{got:08x}"
                want = self.expected.popleft()
                assert got == want, f"cycle {self.cycle()}: proc2mngr got 0x{got:08x}, expected 0x{want:08x}"
                self.gap = random.randint(0, self.max_gap)


async def run_program(dut, mem_image, delays=False, max_cycles=20000, seed=0xDEADBEEF):
    """Load a SparseMemoryImage, run until the source and sink are done.

    Returns (num_cycles, num_insts, memory). num_cycles counts from the end of
    reset; num_insts counts cycles where commit_inst was high.
    """
    random.seed(seed)
    clk = dut.clk
    cocotb.start_soon(Clock(clk, 10, unit="ns").start())

    cycle = 0

    def now():
        return cycle

    memory = Memory()
    src_msgs, sink_msgs = [], []
    for section in mem_image.get_sections():
        words = [w for (w,) in struct.iter_unpack("<I", section.data)]
        if section.name == ".mngr2proc":
            src_msgs += words
        elif section.name == ".proc2mngr":
            sink_msgs += words
        else:
            memory.load_section(section.addr, section.data)

    stall_prob, extra_latency, max_gap = (0.5, 3, 20) if delays else (0.0, 0, 0)
    imem = MemPort(dut, "imem", memory, now, stall_prob, extra_latency)
    dmem = MemPort(dut, "dmem", memory, now, stall_prob, extra_latency)
    src = StreamSource(dut.mngr2proc_val, dut.mngr2proc_rdy, dut.mngr2proc_msg, src_msgs, max_gap)
    sink = StreamSink(dut.proc2mngr_val, dut.proc2mngr_rdy, dut.proc2mngr_msg, sink_msgs, now, max_gap)

    dut.core_id.value = 0
    dut.mngr2proc_val.value = 0
    dut.mngr2proc_msg.value = 0
    dut.proc2mngr_rdy.value = 0
    imem.reset_outputs()
    dmem.reset_outputs()
    dut.reset.value = 1
    for _ in range(3):
        await RisingEdge(clk)
    await FallingEdge(clk)
    dut.reset.value = 0

    for component in (imem, dmem, src, sink):
        cocotb.start_soon(component.run(clk))

    num_insts = 0
    while not (src.done() and sink.done()):
        assert cycle < max_cycles, f"timed out after {max_cycles} cycles"
        await ReadOnly()
        num_insts += int(dut.commit_inst.value)
        await RisingEdge(clk)
        cycle += 1

    return cycle, num_insts, memory
