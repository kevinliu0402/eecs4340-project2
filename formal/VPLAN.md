# Formal verification plan and results: ISR and 8-stage multiplier

This folder holds formal checks for the integer square root (`rtl/ISR.sv`) and the pipelined multiplier it uses (`rtl/mult.sv`, `rtl/mult_stage.sv`). They complement the simulation checks in `sva/` and `uvm/`, which run on VCS.

- **Tools:** SymbiYosys with the Yosys front end, the yices and bitwuzla SMT solvers, and the YosysHQ OSS CAD Suite build from 2026-11-11.
- **The RTL is not edited.** The Makefile pastes each property file into a copy of the module under `build/`.
- **To run:** `make` runs every quick check in about 80 seconds on a laptop.

## Design under test

- ISR samples a 64-bit `value` while `reset` is high.
- It then finds the 32-bit root one bit at a time, from bit 31 down to bit 0.
- For each bit it squares the guess on the multiplier: 1 cycle in TRY_BIT, 8 cycles in WAIT_MULT, then 1 cycle in CHECK_RESULT to keep the bit if guess² ≤ value.
- After the last bit, it pulses `done` once.

## Properties

### ISR control (`isr_props.svh`, task `control`)

| ID | Property |
|---|---|
| C1 | The FSM never reaches IDLE or an unused state encoding. |
| C2 | `done` is high on exactly one cycle: the 321st cycle after reset is released, and never again. |
| C3 | `bit_index` stays in 31..0 while computing, and is 63 (wrapped) after. |
| C4 | The multiplier is started only from TRY_BIT, and its `done` arrives only in WAIT_MULT. |
| C5 | Bits of the result that have not been tried yet are 0. |
| C6 | The sampled input `stored_value` never changes after reset. |
| C7 | The result changes only in CHECK_RESULT, and only by setting the bit being tried. |
| C8 | TRY_BIT is always followed by WAIT_MULT. |
| H1 | Helper invariant for induction: the state and `bit_index` are fixed by the cycle count since reset. |

### ISR algorithm (task `algo`)

The proof is split into two parts.

1. **ISR, with any multiplier output.** The multiplier output is left free. Ghost registers record each square ISR reads, and the number it is the square of. With M(x) meaning the square the multiplier returned for x, the proof shows M(result) ≤ value < M(result + 1) when `done` is high, for every 64-bit value.
2. **The multiplier.** Its own property M2 says M(x) = x · x.

Together these give result = ⌊√value⌋. The split keeps multiplication out of the induction, so the proof finishes in about a second.

| ID | Property |
|---|---|
| A1 | Each product read in CHECK_RESULT was started with both operands equal to the current guess, and the guess does not change while the multiplier runs. |
| A2 | Lower bound: M(result) ≤ value. Upper bound: value < M(hi), where hi = result + 2^(bit_index+1). |
| A3 | When `done` is high, hi = result + 1, so M(result) ≤ value < M(result + 1). |

### Multiplier (`mult_props.svh`, `mult.sby`)

| ID | Property |
|---|---|
| M1 | `done` equals `start` delayed by exactly 8 cycles. A start made during reset never produces a `done`. |
| M2 | `product` is the low 64 bits of `mcand * mplier`, as sampled at `start`. |

### Covers (task `cover`)

- `done` is reached.
- CHECK_RESULT occurs with the guess kept, and with it dropped.

## Results

| Check | Engine | Result | Time |
|---|---|---|---|
| `control`: C1–C8, H1 | smtbmc yices, k-induction (depth 12) | **Proved** for all inputs and all reset timings | 2 s |
| `algo`: A1–A3 | smtbmc yices, k-induction (depth 4) | **Proved** for every 64-bit value | 1 s |
| `cover` | smtbmc yices, depth 330 | All 3 covers reached; `done` at step 322 (1 reset cycle + 321) | 22 s |
| `deep_algo` | BMC, 40 cycles, every property asserted | Pass | 14 s |
| `mult ctrl`: M1 | smtbmc yices, k-induction | **Proved** | 1 s |
| `mult prod8`: M2 | smtbmc bitwuzla, k-induction | **Proved** for operands up to 8 bits | 8 s |
| `mult prod12`: M2 | smtbmc bitwuzla, k-induction | **Proved** for operands up to 12 bits | 56 min |

The 8 partial-product multipliers are cut in every ISR task, so their outputs are free values. The control proof therefore also shows that the control logic does not depend on any product value.

### Mutation check (`make mutants`)

Each bug below is injected on its own into a copy of `ISR.sv`. A bug counts as caught if the control or algo proof stops passing. Each was then confirmed with a concrete failing trace. The tracer tries the proof's base case first, then the 40-cycle BMC, then a 340-cycle Yosys simulation with value = 1001. The unmodified RTL passes the same simulation.

| Bug | Proof | Trace | First property hit |
|---|---|---|---|
| m1: start from bit 30 | control FAIL | base case | H1 |
| m2: finish one bit early | control UNKNOWN | 340-cycle sim | A2 |
| m3: `done` stuck high after FINISH | control UNKNOWN | 340-cycle sim | C2 |
| m4: skip WAIT_MULT | control FAIL | base case | H1 |
| m5: set the wrong bit on keep | control FAIL | base case | C7 |
| m6: `<` instead of `<=` (perfect squares round down) | algo UNKNOWN | 40-cycle BMC | A2 |
| m7: square the old result, not the guess | algo FAIL | base case | A1 |
| m8: compare against live `value`, not `stored_value` | algo UNKNOWN | 40-cycle BMC | A2 |

All 8 mutants are caught. UNKNOWN means the bug broke the induction step but needs a trace longer than the proof's base-case depth.

## Findings

- **Yosys front-end mismatch.** The first M2 run failed: Yosys returned 0xfff × 0xfff = 0xeff1000fef01.
  - VCS, Icarus Verilog and Verilator all compute 0xffe001 on the same RTL.
  - Cause: Yosys sizes `SHIFT'('b0)` in `mult_stage.sv` as 32 bits instead of SHIFT = 8 bits. Inside a concatenation, that shifts `mcand` by 32 instead of 8.
  - The RTL is correct. `build/mult_stage.sv` spells the same zeros as `{SHIFT{1'b0}}`, which every tool reads the same way.
  - This is the kind of simulation/formal semantic mismatch worth checking before trusting a proof.
- **No bugs found in ISR.**

## Limits

- **M2 is proved only for operands up to 12 bits.** Proving that a shift-and-add multiplier equals `*` at 64 bits is out of reach for SAT/SMT-based model checking. The 16-bit run did not finish in a reasonable time. Full-width products are covered in simulation by `sva/isr_mult_sva.sv`.
- **The ISR result proof assumes M2 at full width.** The product ISR reads is the square of a number below 2^32, which is wider than the 12 bits M2 is proved for.
- **The Yosys front end supports only part of SVA.** It covers immediate assertions, `$past` and implication, but not `##` sequences. The properties are written in that style; the concurrent SVA in `sva/` is unchanged.
