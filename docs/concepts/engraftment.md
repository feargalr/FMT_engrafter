# What "engraftment" actually means

Before running anything, it is worth being precise about what we are measuring. Most disagreements between FMT engraftment papers come from different definitions, not different data.

---

## Why species-level profiling fails

Consider a recipient who carries *Bacteroides uniformis* before FMT, receives a donor who also carries *B. uniformis*, and still carries *B. uniformis* afterwards.

A species-level profile (MetaPhlAn, Kraken2, a stock sylph/GTDB run) reports: **no change**.

But there are three biologically distinct things that could have happened:

1. The recipient's own strain persisted; the donor's strain never established.
2. The donor's strain completely replaced the recipient's.
3. Both now coexist.

These have different clinical implications and the species table cannot tell them apart. Human gut species are typically dominated by a **single strain per person**, and that strain is stable for years — so strain identity, not species identity, is the informative unit.

This is why the tutorial builds a reference from the actual genomes in the study rather than profiling against a public database.

---

## The four outcomes

For each genome, compare three sample types. Let **D** = donor material, **Pre** = recipient before FMT, **Post** = recipient after FMT.

| D | Pre | Post | Call | Interpretation |
|:-:|:-:|:-:|---|---|
| ✓ | ✗ | ✓ | **Engraftment** | Donor strain established in the recipient |
| ✓ | ✓ | ✓ | **Persistence (ambiguous)** | Cannot attribute — present in both sources |
| ✗ | ✓ | ✓ | **Persistence** | Recipient's own strain retained |
| ✗ | ✓ | ✗ | **Loss** | Recipient strain cleared |
| ✗ | ✗ | ✓ | **Novel / influx** | From neither source — diet, environment, or below detection earlier |
| ✓ | ✓ | ✗ | **Rejection** | Donor strain failed despite being delivered |

The row that causes most trouble is **D✓ Pre✓ Post✓**. Presence/absence cannot resolve it; you would need strain-resolved SNP comparison (see *Limits*, below) to say whose strain won. Honest practice is to report these as a separate "ambiguous" category rather than silently counting them as engraftment.

> **Design consequence:** without a pre-FMT recipient sample you cannot distinguish row 1 from row 2, and every engraftment number you report will be inflated by the recipient's own pre-existing strains. A pre-FMT sample is not optional.

---

## Detection vs. absence

"Absent" is the weakest claim in the table, and it is doing a lot of work in every row above. A strain scored absent may simply be below the detection limit at that sequencing depth.

Two safeguards:

- **Report the depth.** A genome at 0.01× coverage in a shallowly sequenced sample is not reliably "absent". Sylph's effective coverage estimate is the right quantity to check.
- **Use a consistent detection threshold** across all samples, and state it. Varying the threshold between sample types manufactures engraftment.

This is the main reason the tutorial profiles *every* sample against *the same* database in a single step — so detection is symmetric.

---

## Limits of the approach in this tutorial

Be clear about what this pipeline can and cannot support.

**What it does well.** It establishes, with a cohort-specific reference, which genomes are shared between donor and recipient and at what abundance — a containment-and-ANI measurement over genomes that actually exist in your study.

**Where it stops.** Sylph reports an adjusted ANI per detected genome. ANI is a *genome-wide average*; two distinct strains of the same species commonly sit at 98–99% ANI, and the conventional threshold for "same strain" in the FMT literature is far tighter than ANI can comfortably resolve — typically a population-level SNP identity such as inStrain's **popANI ≥ 99.999%**. Tools built for this (inStrain, StrainPhlAn, SameStr) compare allele frequencies at shared sites rather than averaging over the genome.

So: treat the output of this tutorial as a **strong candidate set** — shared genomes with high ANI and good coverage — and, if the study's claims depend on strain identity rather than genome sharing, follow up those candidates with a SNP-level tool. Stage 4 notes where that handoff belongs.

Claiming strain-level engraftment from ANI alone is the most common overstatement in this area. The pipeline will happily produce a number; the number does not by itself license the claim.

---

## Further reading

- Smillie et al. (2018), *Cell Host & Microbe* — strain engraftment determinants after FMT
- Olm et al. (2021), *Nature Biotechnology* — inStrain and popANI thresholds
- Shaw et al. (2024), *Nature Biotechnology* — sylph method and its ANI estimation
