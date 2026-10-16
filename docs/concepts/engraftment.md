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

## What the count is actually counting

Every genome in the reference is, by construction, a **donor** genome — the database is built from the donor's MAGs and nothing else. So the only question per MAG is what the recipient did with it, and there are four possibilities:

| Pre-FMT | Post-FMT | Meaning |
|:-:|:-:|---|
| ✗ | ✓ | **Engraftment** — donor genome detected after FMT, absent before |
| ✗ | ✗ | **No transfer** — never established, or below detection |
| ✓ | ✓ | **Already present** — the recipient carried it before FMT too |
| ✓ | ✗ | **Lost** — present at baseline, gone afterwards |

The headline number is the count of the first row: donor MAGs detected post-FMT. The reason the **baseline sample matters so much** is the third row. Without it, "already present" and "engraftment" are indistinguishable, and every number is inflated by whatever the recipient happened to share with their donor already.

In practice you do not classify each MAG individually. You count detected MAGs per sample and read the baseline as the floor:

```
baseline:    0 / 124 donor MAGs
post-FMT 1:  5 / 124
post-FMT 2:  7 / 124
```

A baseline at or near zero means the post-FMT counts are attributable to the FMT. A high baseline means they are not, and you should subtract it rather than report the raw number.

> **Design consequence:** a pre-FMT recipient sample is not optional. Without it you have a count with no floor, and no way to say whether it means anything.

---

## Detection vs. absence

"Absent" is the weakest claim in the table, and it is doing a lot of work in every row above. A strain scored absent may simply be below the detection limit at that sequencing depth.

Two safeguards:

- **Report the depth.** A genome at 0.01× coverage in a shallowly sequenced sample is not reliably "absent". Sylph's `Eff_cov` is the right quantity to check — which is why this walkthrough requires ≥1× rather than accepting sylph's much lower detection floor.
- **Use a consistent detection threshold** across all samples, and state it. Varying the threshold between sample types manufactures engraftment.

This is the main reason the tutorial profiles *every* sample against *the same* database in a single step — so detection is symmetric.

---

## Limits of the approach in this tutorial

Be clear about what this pipeline can and cannot support.

**What it does well.** It establishes, with a cohort-specific reference, which of the donor's actual genomes are detectable in the recipient. Because the reference is the donor's own MAG rather than a public representative, a hit is evidence about *that donor's* genome — which is the whole question. The readout is detection: a count of donor MAGs present or absent, not how abundant each one is.

It also recovers some of what the species-level view loses at the top of this page. Because sylph reports hits down to 95% ANI, a recipient strain that is the *same species but a different strain* from a donor MAG appears in the output at its own ANI — below the 99.9% cutoff, but visible. Detecting the donor strain there post-FMT is therefore distinguishable from colonising an empty niche: it is **strain replacement**, exactly the case a species table reports as "no change".

**Where it stops.** Sylph reports ANI to the **best-matching** population in a sample. If the recipient carries their own strain of the same species, it shares most of the donor MAG's genome and can clear a high ANI threshold by itself. The pre-FMT baseline is what resolves this: a relative already present is detected at baseline too, so it lifts the baseline count rather than appearing as engraftment.

The case that slips through is a recipient strain **below detection pre-FMT that blooms afterwards** — absent-then-present looks identical to engraftment. Post-FMT blooms are common, so this is worth checking rather than assuming away.

Two things make it tractable. The ≥1× coverage requirement is strict enough that trace pre-FMT signal rarely passes in one direction and not the other. And profiling every sample against **every** donor database gives you the background rate directly: a recipient matching donors they never received tells you how many chance hits to expect.

So: a count that is large, specific to the recipient's own donor, and sits on a near-zero baseline is strong. A count of one or two, or one that appears against every donor equally, is background. The pipeline will produce a number either way — the number is only as good as the baseline and the cross-donor comparison behind it.

---

## Further reading

- Smillie et al. (2018), *Cell Host & Microbe* — strain engraftment determinants after FMT
- Ianiro et al. (2022), *Nature Medicine* — cross-study FMT strain engraftment meta-analysis
- Shaw & Yu (2024), *Nature Biotechnology* — sylph: containment ANI and its estimation
- [sylph documentation](https://sylph-docs.github.io/) — output format and interpretation
