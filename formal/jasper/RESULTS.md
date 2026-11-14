# JasperGold results: ISR and 8-stage multiplier

Cadence JasperGold 2024.06p002 (FPV, `jasper_fao` license) on the Columbia
micro servers. Same RTL, same properties as the SymbiYosys flow in `../`.

| Script | What it proves | Result | Time |
|---|---|---|---|
| `isr_control.tcl` | Concurrent SVA in `sva/isr_mult_sva.sv`: one-cycle done pulse, multiplier start pulse, exact 8-cycle multiplier latency (from ISR and inside mult), no done without a start | 5/5 proven (unbounded) | < 1 s |
| `isr_algo.tcl` | All of `../isr_props.svh`: control C1-C8, helper H1, algorithm A1-A3 with the multiplier output free (`stopat mult_product`) | 25/25 proven, 28/29 covers reached | 3 s |
| `isr_product.tcl` | `a_product` (product = low 64 bits of mcand*mplier) with operands bounded to W bits | W=8 proven (16 s); W=12, 16 undetermined after 20 min each (24 and 32 not run) | see `product_sweep.txt` |

## Notes

- **Agreement with SymbiYosys.** JasperGold independently proves the same
  25 properties SymbiYosys proved (C1-C8, H1, A1-A3), so the square-root
  result M(result) <= value < M(result+1) holds for every 64-bit input under
  the multiplier contract, in two engines.
- **Multiplier equivalence is the hard part in both tools.** SymbiYosys proved
  12-bit operands in 56 min and did not finish 16 bits; JasperGold proves
  8 bits in 16 s and leaves 12 and 16 bits undetermined at 20 min. Full-width
  products stay covered by simulation (`sva/isr_mult_sva.sv` on VCS).
- **Setup issue found and fixed:** JasperGold black-boxes `*`, `/` and `%`
  wider than its default limit (WNL018). That freed the 8x64 partial products
  and the `f_cyc / 10` schedule in H1 and produced false counterexamples.
  `elaborate -bbox_mul 256 -bbox_div 256 -bbox_mod 256` keeps them.
- The one unreachable cover is the precondition of the SymbiYosys-style
  `assume(reset)` on the first cycle; JasperGold models reset with `reset`.
- JasperGold reads `SHIFT'('b0)` in `mult_stage.sv` correctly, unlike Yosys
  (see `../VPLAN.md`), so the original RTL is used unchanged.
