# The venv lives in the workspace folder above this repo (it isn't committed).
PY      := ../.venv/bin/python
IMPL    ?= alt
K       ?=

.PHONY: help setup test ubmark ubmark-delays compare waves clean

help:
	@echo "make setup          Python venv in ../.venv (once; Verilator installed separately)"
	@echo "make test           all 214 course ISA tests (IMPL=base|alt|bht, K='mul_.*' to filter)"
	@echo "make ubmark         microbenchmarks with cycles / insts / CPI (IMPL=...)"
	@echo "make ubmark-delays  same, with random memory stalls"
	@echo "make compare        ubmark CPI for base vs alt vs bht"
	@echo "make waves K=add_basic   FST waveform in build/\$$IMPL/ (open with gtkwave or Surfer)"

setup:
	/opt/homebrew/bin/python3.10 -m venv ../.venv
	$(PY) -m pip install -q --upgrade pip
	$(PY) -m pip install -q -r requirements.txt

test:
	$(PY) tb/run.py isa --impl $(IMPL) $(if $(K),-k '$(K)')

ubmark:
	$(PY) tb/run.py ubmark --impl $(IMPL)

ubmark-delays:
	$(PY) tb/run.py ubmark --impl $(IMPL) --mem-delays

compare:
	$(PY) tb/run.py ubmark --impl base
	$(PY) tb/run.py ubmark --impl alt
	$(PY) tb/run.py ubmark --impl bht

waves:
	$(PY) tb/run.py isa --impl $(IMPL) -k '$(K)' --waves

clean:
	rm -rf build
