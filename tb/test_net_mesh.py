"""Tests for the 2x2 net_Mesh.

random_traffic: every terminal sends to random destinations with random
sink stalls; each packet must arrive once, at the right terminal, in
order per (src, dest) pair.

latency_sweep: Bernoulli injection at increasing rates; logs average
latency and throughput per rate, and writes them to $RESULTS_FILE.
"""

import json
import os
import random

import cocotb
from cocotb.triggers import RisingEdge

from net_harness import Sink, Source, pack, reset, run_until, unpack

NUM_TERMINALS = 4


@cocotb.test()
async def random_traffic(dut):
    random.seed(0xBEEF)
    await reset(dut)

    src = Source(dut.in_val, dut.in_rdy, dut.in_msg, NUM_TERMINALS, max_gap=2)
    sink = Sink(dut.out_val, dut.out_rdy, dut.out_msg, NUM_TERMINALS, stall_prob=0.3)

    expected = {}
    for t in range(NUM_TERMINALS):
        for seq in range(300):
            dest = random.randrange(NUM_TERMINALS)
            src.queues[t].append(pack(src=t, dest=dest, data=seq))
            expected.setdefault((t, dest), []).append(seq)

    received = {key: [] for key in expected}
    errors = []

    def on_recv(terminal, msg):
        m = unpack(msg)
        if m["dest"] != terminal:
            errors.append(f"packet {m['src']}->{m['dest']} seq {m['data']} arrived at terminal {terminal}")
        received.setdefault((m["src"], m["dest"]), []).append(m["data"])

    sink.on_recv = on_recv
    cocotb.start_soon(src.run(dut.clk))
    cocotb.start_soon(sink.run(dut.clk))

    total = sum(len(v) for v in expected.values())
    await run_until(dut, lambda: sum(len(v) for v in received.values()) >= total or errors, 30000)
    assert not errors, "\n".join(errors[:10])
    for key, want in expected.items():
        assert received[key] == want, (
            f"{key[0]}->{key[1]}: got {len(received[key])} packets, expected {len(want)}, or out of order")


@cocotb.test()
async def latency_sweep(dut):
    random.seed(0xCAFE)
    await reset(dut)

    src = Source(dut.in_val, dut.in_rdy, dut.in_msg, NUM_TERMINALS)
    sink = Sink(dut.out_val, dut.out_rdy, dut.out_msg, NUM_TERMINALS)

    now = [0]
    created = {}
    latencies = []
    next_id = 0

    async def count_cycles():
        while True:
            await RisingEdge(dut.clk)
            now[0] += 1

    def on_recv(terminal, msg):
        pid = unpack(msg)["data"]
        latencies.append(now[0] - created.pop(pid))

    sink.on_recv = on_recv
    cocotb.start_soon(count_cycles())
    cocotb.start_soon(src.run(dut.clk))
    cocotb.start_soon(sink.run(dut.clk))

    results = []
    for rate in [0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]:
        latencies.clear()
        injected_cycles = 1000
        for _ in range(injected_cycles):
            for t in range(NUM_TERMINALS):
                if random.random() < rate:
                    dest = random.choice([d for d in range(NUM_TERMINALS) if d != t])
                    created[next_id] = now[0]
                    src.queues[t].append(pack(src=t, dest=dest, data=next_id))
                    next_id += 1
            await RisingEdge(dut.clk)
        await run_until(dut, lambda: not created, 20000)
        avg = sum(latencies) / len(latencies) if latencies else float("nan")
        throughput = len(latencies) / (injected_cycles * NUM_TERMINALS)
        results.append({"rate": rate, "avg_latency": round(avg, 2), "throughput": round(throughput, 3)})
        dut._log.info(f"injection {rate:.2f}/node/cycle: avg latency {avg:6.2f} cycles, "
                      f"throughput {throughput:.3f}/node/cycle")

    results_file = os.environ.get("RESULTS_FILE")
    if results_file:
        with open(results_file, "w") as f:
            json.dump(results, f, indent=2)
