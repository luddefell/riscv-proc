"""Exhaustive test of net_MeshRouteUnit: every (router, dest) pair in a 2x2 mesh."""

import cocotb
from cocotb.triggers import Timer

from net_harness import PORT_NAMES, xy_port


@cocotb.test()
async def xy_routing(dut):
    errors = []
    for router_id in range(4):
        for dest in range(4):
            dut.router_id.value = router_id
            dut.dest.value = dest
            await Timer(1, unit="ns")
            want = 1 << xy_port(router_id, dest)
            got = int(dut.route.value)
            if got != want:
                errors.append(f"router {router_id} dest {dest}: route={got:05b}, "
                              f"expected {want:05b} ({PORT_NAMES[xy_port(router_id, dest)]})")
    assert not errors, "\n".join(errors)
