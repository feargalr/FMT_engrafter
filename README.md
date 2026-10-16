# FMT_engrafter

A walkthrough for **counting donor strain engraftment after faecal microbiota transplantation (FMT)** from shotgun metagenomes, run on **Pawsey's Setonix**.

This is a tutorial, not a pipeline. It walks through five steps, with example code at each one:

> **assemble → bin → quality control → sylph → filter and count**

---

## The idea

After an FMT we want to know: **how many of the donor's microbial genomes can we find in the recipient afterwards that were not there before?**

The approach is reference-free. Rather than profiling against a public database — which almost certainly does not contain the donor's actual strains — we **reconstruct genomes from the donor material itself** and use those as the reference. Then every recipient sample is matched against them.

```
  Donor FMT material                    Recipient samples
   (raw FASTQ)                     (pre-FMT, post-FMT timepoints)
        │                                      │
        ▼                                      │
  ┌───────────────┐                            │
  │ 1. assemble   │  OpusTaxa: QC, host        │  same QC and
  │               │  removal, metaSPAdes       │  host removal
  └───────┬───────┘                            │
          ▼                                    │
  ┌───────────────┐                            │
  │ 2. bin        │  nf-core/mag → MAGs        │
  └───────┬───────┘                            │
          ▼                                    │
  ┌───────────────┐                            │
  │ 3. QC         │  CheckM2 → filter          │
  └───────┬───────┘                            │
          ▼                                    │
  ┌───────────────┐                            │
  │ 4. sylph      │  one database per donor ◄──┘
  │               │  profile every sample against every donor
  └───────┬───────┘
          ▼
  ┌───────────────┐
  │ 5. filter     │  ANI ≥ 99.9%, coverage ≥ 1×
  │    and count  │  → MAGs shared with donor, per sample
  └───────────────┘
```

**One database per donor.** Each donor's MAGs become their own sylph database, and every recipient sample is profiled against each. This keeps donor provenance exact — a hit is unambiguously against *that donor's* genome — and avoids any need to dereplicate across donors.

---

## What this assumes, and what it measures

**The design.** Per recipient, three sample types:

| Sample | Role |
|---|---|
| **Donor FMT material** | The material actually administered. Source of the reference genomes. |
| **Recipient pre-FMT** | Baseline. Establishes what the recipient already carried. |
| **Recipient post-FMT** | One or more timepoints. Where engraftment is read out. |

Without the pre-FMT baseline you cannot tell engraftment from strains the recipient already had.

**The readout is a count, not abundance.** The final table is: *for each sample, how many of the donor's MAGs were detected.* Expressed as a fraction of that donor's catalogue it gives a percentage. sylph reports abundance columns; this walkthrough ignores them.

A healthy result looks like near-zero at baseline, rising after FMT:

| Sample | Timepoint | MAGs shared with donor | Donor MAGs total | % |
|---|---|---|---|---|
| `RecipA_t0` | baseline | 1 | 108 | 0.9 |
| `RecipA_t1` | post-FMT | 34 | 108 | 31.5 |
| `RecipA_t2` | post-FMT | 29 | 108 | 26.9 |

---

## The walkthrough

| Step | Guide | Tool |
|---|---|---|
| 0 | [Setup on Setonix](docs/00-setup-setonix.md) | modules, storage, accounts |
| 1 | [Assemble](docs/01-assemble.md) | OpusTaxa (Snakemake + Singularity) |
| 2 | [Bin](docs/02-bin.md) | nf-core/mag |
| 3 | [Quality control](docs/03-quality-control.md) | CheckM2 |
| 4 | [Sylph](docs/04-sylph.md) | sylph |
| 5 | [Filter and count](docs/05-filter-and-count.md) | awk / R |

Example SLURM scripts and configs are in [`scripts/`](scripts/). They are templates — paths, project codes and donor names are placeholders you replace.

Background: **[what engraftment means](docs/concepts/engraftment.md)**, and what a count like this does and does not support.

---

## Before you start

- A Pawsey account and project code (`pawseyXXXX`)
- Paired-end shotgun metagenomes: donor material, recipient pre-FMT, recipient post-FMT
- Roughly 1–2 TB of `$MYSCRATCH` for a mid-sized cohort

---

## Tools

- **[OpusTaxa](https://github.com/yenkaiC/OpusTaxa)** — QC, host removal, assembly. Also supplies the Singularity containers reused in step 4.
- **[nf-core/mag](https://nf-co.re/mag)** — binning and MAG QC.
- **[sylph](https://github.com/bluenote-1577/sylph)** — containment-based profiling against the donor databases.
