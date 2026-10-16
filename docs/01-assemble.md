# Step 1 — Assemble: QC, host removal and assembly

[OpusTaxa](https://github.com/yenkaiC/OpusTaxa) is a Snakemake metagenomics pipeline. We use it here for three things:

1. **Quality control** (fastp) — trim and filter reads
2. **Host read removal** (NoHuman) — strip human sequence
3. **Assembly** (metaSPAdes) — produce `scaffolds.fasta` per sample

Run it on **every** sample — donors and recipients alike. The donor assemblies become MAGs in step 2; the recipients only need the host-removed reads, which step 4 matches against those MAGs.

We deliberately do **not** run the taxonomic profilers here. The profiling that matters happens in step 4, against the donor genomes rather than a public database.

A side benefit: OpusTaxa ships Singularity containers for every tool, including sylph. Step 4 reuses that sylph container rather than installing anything new.

---

## Why host removal matters here

Human reads in a gut metagenome are usually a small fraction, but they are poison for this particular analysis. They assemble into contigs, those contigs get binned, and you end up with "MAGs" that are fragments of human chromosome. Those then enter your sylph database as reference genomes, and every sample matches them — producing beautifully consistent, entirely artefactual "engraftment".

Run host removal. It is on by default in OpusTaxa and should stay on.

---

## Install

From the login node, inside your `screen` session:

```bash
cd $MYSCRATCH/FMT_engrafter
git clone https://github.com/yenkaiC/OpusTaxa.git
cd OpusTaxa
conda activate snakemake
module load singularity/4.1.0-slurm
```

---

## Set your project code

```bash
nano config/slurm_singularity/config.yaml
```

Under `default-resources`, set your allocation:

```yaml
default-resources:
  - "slurm_account=pawseyXXXX"     # <-- your project code
  - "slurm_partition=work"
```

---

## Organise your input

OpusTaxa reads paired-end FASTQ from `Data/Raw_FastQ/`, or any directory you point it at:

```bash
snakemake --workflow-profile config/slurm_singularity \
    --config inputFastQDirectory=/scratch/pawseyXXXX/yourusername/fastq
```

It auto-detects and standardises common naming conventions (Illumina bcl2fastq, SRA, ENA, dot-separated) by symlinking — your original files are never modified. Both `.fastq.gz` and `.fq.gz` work.

### Keep a sample manifest

Record what each sample *is*, while you still remember which tube was which. Every table in step 5 is a join against this.

| sample_id | participant | sample_type | timepoint | donor |
|---|---|---|---|---|
| `D1` | — | donor | NA | — |
| `D2` | — | donor | NA | — |
| `RecipA_t0` | RecipA | recipient | baseline | `D2` |
| `RecipA_t1` | RecipA | recipient | post-FMT | `D2` |
| `RecipA_t2` | RecipA | recipient | post-FMT | `D2` |

- **`sample_id`** must match the FASTQ basename OpusTaxa uses — it is the join key throughout.
- **`timepoint`** — mark the pre-FMT baseline clearly. Keep labels sortable as strings.
- **`donor`** — which donor this recipient received. This is what lets you read the step 5 table correctly: a recipient should match *their own* donor, not the others.

Step 4 also needs a second, much simpler manifest — just `sample`, `R1`, `R2`, tab-separated — to drive the sylph job array. You generate that from the FASTQ directory rather than writing it by hand.

> **Donor material matters.** The donor sample must be the *material actually administered*, not a separate donor stool collection from a different date. Donor strain content varies between donations.

---

## Dry run first

Always. This shows every job Snakemake would submit without submitting anything:

```bash
snakemake --workflow-profile config/slurm_singularity --dry-run \
    --config metaspades=true
```

If it prints a job list and exits cleanly, you are ready.

---

## Run

```bash
snakemake --workflow-profile config/slurm_singularity \
    --config metaspades=true
```

`metaspades=true` is the flag that matters — assembly is off by default. QC, host removal and the FastQC/MultiQC reports are always on.

Detach from `screen` with **Ctrl+A** then **D**. Reattach with `screen -r fmt`.

### If your data is public

For reanalysis of a published FMT cohort, put SRA run accessions in `sra_id.txt` (one per line) and add `download_sra=true`:

```bash
snakemake --workflow-profile config/slurm_singularity \
    --config download_sra=true metaspades=true
```

> **Start with 2–3 samples.** Verify the whole chain works before committing a full cohort. OpusTaxa will not re-run samples it has already processed, so scaling up afterwards costs nothing.

---

## Assembly is the expensive step

metaSPAdes dominates the runtime and memory of this step. The OpusTaxa defaults request 20 threads per sample; deep samples may need more time than the default walltime allows.

If assemblies are being killed on walltime, raise it in the profile's `set-resources`:

```yaml
set-resources:
  - "metaspades:runtime=2880"      # 48 hours
  - "metaspades:jobs=15"           # limit concurrent assemblies
```

Capping concurrency matters as much as raising walltime — a cohort of large assemblies launched all at once will sit in the queue competing with itself.

---

## Output

The files that matter downstream:

```
OpusTaxa/Data/
├── NoHuman/                      # host-removed reads  → needed for binning coverage
│   ├── {sample}_R1_001.fastq.gz
│   └── {sample}_R2_001.fastq.gz
└── MetaSPAdes/
    └── {sample}/
        ├── contigs.fasta
        └── scaffolds.fasta       # → input to nf-core/mag
```

**Both** are needed later. The assemblies supply the contigs to bin; the host-removed reads supply the coverage signal that binning algorithms use to group contigs. Do not delete the NoHuman reads after assembly — steps 2 and 4 both need them.

---

## Check before moving on

Look at `Reports/MultiQC/` and `Data/NoHuman/nohuman_summary.tsv`:

- **Host fraction** — high human content (say >50%) means fewer microbial reads than your depth suggests, and will produce fragmentary assemblies. Worth knowing before you blame the binner.
- **Read counts after fastp** — a sample that lost most of its reads to QC will not assemble well.
- **Assembly presence** — confirm `scaffolds.fasta` exists and is non-trivial for *every* sample:

```bash
for f in Data/MetaSPAdes/*/scaffolds.fasta; do
    printf '%s\t%s\n' "$f" "$(grep -c '^>' "$f")"
done
```

A sample with very few scaffolds will yield no usable bins. Decide now whether to drop it or sequence it deeper — a donor sample that fails here undermines the whole analysis, since donor MAGs are the reference everything else is matched against.

Next: **[Step 2 — Bin](02-bin.md)**
