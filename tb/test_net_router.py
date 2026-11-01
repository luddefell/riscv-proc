"""Random-traffic tests for one net_MeshRouter.

Every packet must leave through the port XY routing picks, exactly once,
and packets from the same input to the same output must stay in order.
"""

import random

import cocotb

from net_harness import (PORT_NAMES, Sink, Source, pack, reset, run_until, unpack, xy_port)

PACKETS_PER_INPUT = 200


async def random_traffic(dut, router_id, max_gap, stall_prob, seed):
    random.seed(seed)
    await reset(dut)
    dut.router_id.value = router_id

    src = Source(dut.in_val, dut.in_rdy, dut.in_msg, 5, max_gap)
    sink = Sink(dut.out_val, dut.out_rdy, dut.out_msg, 5, stall_prob)

    expected = {}  # (input, output) -> list of data in send order
    for i in range(5):
        for seq in range(PACKETS_PER_INPUT):
            dest = random.randrange(4)
            data = (i << 16) | seq
            src.queues[i].append(pack(src=0, dest=dest, data=data))
            expected.setdefault((i, xy_port(router_id, dest)), []).append(data)

    received = {key: [] for key in expected}
    errors = []

    def on_recv(port, msg):
        m = unpack(msg)
        i = m["data"] >> 16
        want = xy_port(router_id, m["dest"])
        if port != want:
            errors.append(f"input {i} seq {m['data'] & 0xFFFF} dest {m['dest']} left via "
                          f"{PORT_NAMES[port]}, expected {PORT_NAMES[want]}")
        received.setdefault((i, port), []).append(m["data"])

    sink.on_recv = on_recv
    cocotb.start_soon(src.run(dut.clk))
    cocotb.start_soon(sink.run(dut.clk))

    total = 5 * PACKETS_PER_INPUT
    await run_until(dut, lambda: sum(len(v) for v in received.values()) >= total or errors, 20000)
    assert not errors, "\n".join(errors[:10])
    for key, want in expected.items():
        assert received[key] == want, (
            f"input {PORT_NAMES[key[0]]} -> output {PORT_NAMES[key[1]]}: "
            f"got {len(received[key])} packets, expected {len(want)}, or out of order")


def _register(name, router_id, max_gap, stall_prob, seed):
    # One cocotb test per case, so each starts with a fresh clock and drivers.
    async def test(dut):
        await random_traffic(dut, router_id, max_gap, stall_prob, seed)
    test.__name__ = test.__qualname__ = name
    globals()[name] = cocotb.test()(test)


for _rid in range(4):
    _register(f"router{_rid}_no_stalls", _rid, max_gap=0, stall_prob=0.0, seed=_rid)
    _register(f"router{_rid}_with_stalls", _rid, max_gap=3, stall_prob=0.5, seed=10 + _rid)
