"""Tests for sys_CacheNet.

random_traffic: each proc sends random reads/writes to random addresses;
a mock bank on each cache port checks the request landed on bank
addr[5:4], then answers with the request's data and echoed opaque. Every
proc must get back exactly its own responses, each exactly once.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

from net_harness import Sink, Source, run_until

NUM_PORTS = 4
REQ_NBITS = 78
RESP_NBITS = 48


# mem_req_4B_t: type[77:74] opaque[73:66] addr[65:34] len[33:32] data[31:0]
def pack_req(type_, addr, data, opaque=0, len_=0):
    return (type_ << 74) | (opaque << 66) | (addr << 34) | (len_ << 32) | data


def unpack_req(v):
    return dict(type_=(v >> 74) & 0xF, opaque=(v >> 66) & 0xFF, addr=(v >> 34) & 0xFFFF_FFFF,
                data=v & 0xFFFF_FFFF)


# mem_resp_4B_t: type[47:44] opaque[43:36] test[35:34] len[33:32] data[31:0]
def pack_resp(type_, opaque, data):
    return (type_ << 44) | (opaque << 36) | data


def unpack_resp(v):
    return dict(type_=(v >> 44) & 0xF, opaque=(v >> 36) & 0xFF, data=v & 0xFFFF_FFFF)


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.reset.value = 1
    dut.procreq_val.value = 0
    dut.procresp_rdy.value = 0
    dut.cachereq_rdy.value = 0
    dut.cacheresp_val.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.reset.value = 0


@cocotb.test()
async def random_traffic(dut):
    random.seed(0xCAFE)
    await reset(dut)

    procs = Source(dut.procreq_val, dut.procreq_rdy, dut.procreq_msg, NUM_PORTS, max_gap=2, nbits=REQ_NBITS)
    proc_sink = Sink(dut.procresp_val, dut.procresp_rdy, dut.procresp_msg, NUM_PORTS, stall_prob=0.3,
                     nbits=RESP_NBITS)
    bank_sink = Sink(dut.cachereq_val, dut.cachereq_rdy, dut.cachereq_msg, NUM_PORTS, stall_prob=0.3,
                     nbits=REQ_NBITS)
    banks = Source(dut.cacheresp_val, dut.cacheresp_rdy, dut.cacheresp_msg, NUM_PORTS, max_gap=3,
                   nbits=RESP_NBITS)

    # data = {proc[31:28], seq[27:0]} so every request is unique and names its sender
    expected = {p: set() for p in range(NUM_PORTS)}
    for p in range(NUM_PORTS):
        for seq in range(200):
            data = (p << 28) | seq
            procs.queues[p].append(pack_req(random.randrange(2), random.randrange(1 << 16) & ~3, data))
            expected[p].add(data)

    received = {p: [] for p in range(NUM_PORTS)}
    errors = []

    def on_bank_recv(bank, msg):
        req = unpack_req(msg)
        if (req["addr"] >> 4) & 3 != bank:
            errors.append(f"addr {req['addr']:#x} arrived at bank {bank}")
        banks.queues[bank].append(pack_resp(req["type_"], req["opaque"], req["data"]))

    def on_proc_recv(proc, msg):
        resp = unpack_resp(msg)
        if resp["data"] >> 28 != proc:
            errors.append(f"proc {resp['data'] >> 28}'s response {resp['data']:#x} arrived at proc {proc}")
        received[proc].append(resp["data"])

    bank_sink.on_recv = on_bank_recv
    proc_sink.on_recv = on_proc_recv
    for task in (procs, proc_sink, bank_sink, banks):
        cocotb.start_soon(task.run(dut.clk))

    total = sum(len(v) for v in expected.values())
    await run_until(dut, lambda: sum(len(v) for v in received.values()) >= total or errors, 40000)
    assert not errors, "\n".join(errors[:10])
    for p in range(NUM_PORTS):
        assert len(received[p]) == len(set(received[p])), f"proc {p} got a duplicate response"
        assert set(received[p]) == expected[p], f"proc {p}: {len(expected[p] - set(received[p]))} responses missing"
