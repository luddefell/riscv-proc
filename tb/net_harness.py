"""cocotb helpers for the mesh network tests.

Messages use the vc/net-msgs.v layout: {src[2], dest[2], opaque[8], data}.
Several val/rdy ports share one flattened msg vector, so each Source/Sink
drives or samples all ports of a bus at once.
"""

import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge

MSG_NBITS = 44
DATA_NBITS = MSG_NBITS - 12

PORT_N, PORT_S, PORT_E, PORT_W, PORT_L = range(5)
PORT_NAMES = "NSEWL"


def pack(src, dest, data, opaque=0):
    return (src << (MSG_NBITS - 2)) | (dest << (MSG_NBITS - 4)) | (opaque << DATA_NBITS) | data


def unpack(msg):
    return dict(src=(msg >> (MSG_NBITS - 2)) & 3, dest=(msg >> (MSG_NBITS - 4)) & 3,
                opaque=(msg >> DATA_NBITS) & 0xFF, data=msg & ((1 << DATA_NBITS) - 1))


def xy_port(router_id, dest, width=2):
    """Reference XY routing: x first, then y. Node ID = {y, x}."""
    x, y = router_id % width, router_id // width
    dx, dy = dest % width, dest // width
    if dx > x:
        return PORT_E
    if dx < x:
        return PORT_W
    if dy > y:
        return PORT_S
    if dy < y:
        return PORT_N
    return PORT_L


def get_slice(vec, i):
    return (vec >> (i * MSG_NBITS)) & ((1 << MSG_NBITS) - 1)


class Source:
    """Drives n val/rdy ports from per-port queues, with optional random gaps."""

    def __init__(self, val, rdy, msg, n, max_gap=0):
        self.val, self.rdy, self.msg, self.n = val, rdy, msg, n
        self.queues = [deque() for _ in range(n)]
        self.max_gap = max_gap
        self.gap = [0] * n
        self.on_send = None

    def done(self):
        return all(not q for q in self.queues)

    async def run(self, clk):
        while True:
            await FallingEdge(clk)
            sending = [bool(self.queues[i]) and self.gap[i] == 0 for i in range(self.n)]
            self.val.value = sum(1 << i for i in range(self.n) if sending[i])
            self.msg.value = sum(self.queues[i][0] << (i * MSG_NBITS) for i in range(self.n) if sending[i])

            await ReadOnly()
            rdy = int(self.rdy.value)
            fired = [sending[i] and (rdy >> i) & 1 for i in range(self.n)]

            await RisingEdge(clk)
            for i in range(self.n):
                if self.gap[i]:
                    self.gap[i] -= 1
                if fired[i]:
                    msg = self.queues[i].popleft()
                    if self.on_send:
                        self.on_send(i, msg)
                    self.gap[i] = random.randint(0, self.max_gap)


class Sink:
    """Accepts n val/rdy ports, with rdy dropped at random (stall_prob)."""

    def __init__(self, val, rdy, msg, n, stall_prob=0.0):
        self.val, self.rdy, self.msg, self.n = val, rdy, msg, n
        self.stall_prob = stall_prob
        self.on_recv = None

    async def run(self, clk):
        while True:
            await FallingEdge(clk)
            ready = [random.random() >= self.stall_prob for _ in range(self.n)]
            self.rdy.value = sum(1 << i for i in range(self.n) if ready[i])

            await ReadOnly()
            val, msg = int(self.val.value), int(self.msg.value)
            got = [(i, get_slice(msg, i)) for i in range(self.n) if ready[i] and (val >> i) & 1]

            await RisingEdge(clk)
            for i, m in got:
                self.on_recv(i, m)


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.reset.value = 1
    dut.in_val.value = 0
    dut.out_rdy.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.reset.value = 0


async def run_until(dut, cond, max_cycles):
    cycles = 0
    while not cond():
        assert cycles < max_cycles, f"timed out after {max_cycles} cycles"
        await RisingEdge(dut.clk)
        cycles += 1
    return cycles
