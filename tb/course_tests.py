"""Collects the course's lab2 assembly tests without running PyMTL.

The ProcFL_*_test.py files list every gen_*_test function through
@pytest.mark.parametrize, and each test_<inst>_delays method reruns
inst_<inst>.gen_random_test with random memory and stream delays. This
module reads those lists so the cocotb run covers exactly the same cases.
"""

import importlib
import inspect
import sys
import types

GROUPS = ["rr", "rimm", "mem", "branch", "jump", "csr"]


def _stub_pymtl_harness():
    """The course harness and ProcFL need a newer PyMTL3 stdlib than PyPI
    ships. Only asm_test is needed to read the test lists, so stand in for
    both modules before the test files import them."""
    harness = types.ModuleType("lab2_proc.test.harness")

    def asm_test(func):
        name = func.__name__
        if name.startswith("gen_"):
            name = name[4:]
        if name.endswith("_test"):
            name = name[:-5]
        return (name, func)

    harness.asm_test = asm_test
    harness.run_test = None
    sys.modules.setdefault("lab2_proc.test.harness", harness)

    proc_fl = types.ModuleType("lab2_proc.ProcFL")
    proc_fl.ProcFL = None
    sys.modules.setdefault("lab2_proc.ProcFL", proc_fl)


def collect():
    """Returns a sorted list of (name, gen_func, delays)."""
    _stub_pymtl_harness()
    cases = {}
    for group in GROUPS:
        module = importlib.import_module(f"lab2_proc.test.ProcFL_{group}_test")
        for meth_name, meth in inspect.getmembers(module.Tests, inspect.isfunction):
            if not meth_name.startswith("test_"):
                continue
            inst = meth_name[len("test_"):]
            if inst.endswith("_delays"):
                inst = inst[: -len("_delays")]
                inst_mod = importlib.import_module(f"lab2_proc.test.inst_{inst}")
                cases[f"{inst}_delays"] = (inst_mod.gen_random_test, True)
                continue
            for mark in getattr(meth, "pytestmark", []):
                if mark.name != "parametrize":
                    continue
                for name, gen in mark.args[1]:
                    cases[f"{inst}_{name}"] = (gen, False)
    return [(name, gen, delays) for name, (gen, delays) in sorted(cases.items())]
