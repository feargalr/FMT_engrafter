# FMT_engrafter

A step-by-step tutorial for **assessing bacterial strain engraftment after faecal microbiota transplantation (FMT)** from shotgun metagenomes, run end-to-end on **Pawsey's Setonix** supercomputer.

This repository is a *tutorial*, not a pipeline. It stitches together three existing, well-maintained tools and explains the reasoning at each step — what each stage produces, why it is needed, and where the biology can mislead you.

---

## The question this answers

After an FMT, we want to know: **which bacterial strains in the recipient's post-FMT gut came from the donor?**

A strain is either:

| Outcome | Meaning |
|---|---|
| **Engrafted** | Present in the donor material, absent in the recipient pre-FMT, present in the recipient post-FMT |
| **Persistent** | Present in the recipient pre-FMT and still present post-FMT |
| **Novel** | Present post-FMT but in neither the donor nor the recipient pre-FMT |
| **Lost** | Present in the recipient pre-FMT, absent post-FMT |

Species-level profiling is not enough: donor and recipient routinely carry *different strains of the same species*, so a species-level table shows "no change" where a complete strain replacement actually happened. Everything in this tutorial is built around getting below the species line.

Answering this needs **strain-level** resolution — see [docs/concepts/engraftment.md](docs/concepts/engraftment.md) for why, and for what this approach can and cannot support.

---

## The approach

The core idea is **reference-free**: rather than matching samples against a generic public database (which may not contain the donor's actual strains at all), we build genomes *from the donor material and the recipients themselves*, then use those genomes as the reference.

```
   Raw FASTQ (donor material, recipient pre-FMT, recipient post-FMT)
            │
   ┌────────▼─────────┐
   │ 1. OpusTaxa      │  QC → host removal → metaSPAdes assembly
   └────────┬─────────┘  ⇒ scaffolds.fasta per sample
            │
   ┌────────▼─────────┐
   │ 2. nf-core/mag   │  binning → bin QC → taxonomy
   └────────┬─────────┘  ⇒ dereplicated, quality-filtered MAGs
            │
   ┌────────▼─────────┐
   │ 3. sylph DB      │  build a custom database from those MAGs
   └────────┬─────────┘  ⇒ cohort-specific .syldb
            │
   ┌────────▼─────────┐
   │ 4. Profile       │  match every sample against the custom DB
   └────────┬─────────┘  ⇒ per-genome abundance + ANI per sample
            │
      Engraftment calls
```

Why this ordering matters: step 3 is only meaningful because of step 2. A sylph database built from *your own* donor MAGs lets you ask "is **this specific donor genome** present in the recipient post-FMT?" — a question a public GTDB database cannot answer, because the donor's strain is almost certainly not in GTDB.

---

## Tutorial stages

| Stage | Guide | What it does |
|---|---|---|
| 0 | [Setonix setup](docs/00-setup-setonix.md) | Accounts, storage, modules, persistent sessions |
| 1 | [OpusTaxa](docs/01-opustaxa.md) | QC, host-read removal, metaSPAdes assembly |
| 2 | [nf-core/mag](docs/02-nfcore-mag.md) | Binning and bin QC from the assemblies |
| 3 | [Custom sylph database](docs/03-sylph-custom-db.md) | Build a cohort-specific reference from the MAGs |
| 4 | [Engraftment analysis](docs/04-engraftment-analysis.md) | Profile samples, call engraftment, interpret |

Work through them in order. Every step is a copy-pasteable snippet — there is no wrapper pipeline to install, and nothing here hides a step from you.

Background reading: **[what engraftment actually means](docs/concepts/engraftment.md)** — definitions, the four outcomes, and the limits of calling strains this way.

---

## Tools used

- **[OpusTaxa](https://github.com/yenkaiC/OpusTaxa)** — Snakemake metagenomics pipeline (Chen et al.). Used here for QC, host removal and assembly. Also supplies the Singularity containers reused in stage 3.
- **[nf-core/mag](https://nf-co.re/mag)** — Nextflow pipeline for metagenome binning and MAG QC.
- **[sylph](https://github.com/bluenote-1577/sylph)** — ultrafast containment-based profiler; used against a custom database.

All three run from Singularity containers on Setonix. Nothing here needs conda beyond the Snakemake launcher.

---

## Before you start

You will need:

- A Pawsey account and a project code (`pawseyXXXX`)
- Paired-end shotgun metagenomes with a design that includes, at minimum, **donor material**, **recipient pre-FMT** and **recipient post-FMT** samples
- Roughly 1–2 TB of `$MYSCRATCH` for a mid-sized cohort (assemblies and bins dominate)

A design without a pre-FMT recipient sample cannot distinguish engraftment from persistence. This is the single most common design flaw — see [the concepts guide](docs/concepts/engraftment.md).

---

## Licence

See [LICENSE](LICENSE).
