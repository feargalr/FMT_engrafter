# Step 2 — Bin: reconstructing donor genomes

A metagenomic assembly is thousands of contigs from hundreds of organisms, with nothing saying which contig belongs to which genome. **Binning** groups contigs that look like they came from the same organism, using sequence composition and coverage. Each bin is a **metagenome-assembled genome (MAG)**.

```
   Donor assembly (scaffolds.fasta)
              │
      thousands of contigs
              │
        genome binning
              │
      ┌───────┼───────┐
      ▼       ▼       ▼
    MAG1    MAG2    MAG3
```

We bin **only the donor samples** — their MAGs become the reference. Recipient samples are never binned; they are matched against the donor MAGs as reads in step 4. That is what keeps this tractable for a longitudinal cohort.

---

## Set up

```bash
cd $MYSCRATCH/FMT_engrafter
mkdir -p donor_MAGs && cd donor_MAGs

module load nextflow/25.04.6
module load singularity/4.1.0-slurm
```

### Nextflow config

Copy [`scripts/nextflow.config`](../scripts/nextflow.config) here and edit the project code and paths:

```groovy
process {
    executor       = 'slurm'
    queue          = 'work'
    clusterOptions = '--account=pawseyXXXX'

    // Nextflow runs on a login node where Singularity is available, but each
    // SLURM job gets its own environment - load the module inside every job.
    beforeScript = '''
        module load singularity/4.1.0-slurm
    '''

    cache       = 'lenient'      // required for -resume on Lustre
    stageInMode = 'symlink'      // don't copy large FASTQ into every work dir
}

workDir = '/scratch/pawseyXXXX/youruser/nxf_work'

singularity {
    enabled    = true
    autoMounts = true
    cacheDir   = '/software/projects/pawseyXXXX/youruser/.nextflow_singularity'
}
```

Keep `workDir` on scratch — Nextflow work directories are enormous. The `cacheDir` on `/software` means container images are downloaded once, not per run.

> There is also an official `pawsey_setonix` nf-core profile that sets most of this for you, reading your account from `$PAWSEY_PROJECT`. The explicit config above is what this walkthrough was run with, and is easier to debug when something goes wrong.

---

## The two samplesheets

nf-core/mag needs **two** CSVs: one for reads, one for the assemblies. Reads are still required even though you are supplying assemblies — they are mapped back to the contigs to get the coverage signal binning depends on.

### `samplesheet.csv` — reads

Use the **host-removed** reads from step 1. With `--assembly_input` set, the pipeline skips its own trimming and host removal, so whatever you give it is used as-is.

```csv
sample,group,short_reads_1,short_reads_2,short_reads_platform
D1,D1,/scratch/pawseyXXXX/youruser/proj/OpusTaxa/Data/NoHuman/D1_R1_001.fastq.gz,/scratch/pawseyXXXX/youruser/proj/OpusTaxa/Data/NoHuman/D1_R2_001.fastq.gz,ILLUMINA
D2,D2,/scratch/pawseyXXXX/youruser/proj/OpusTaxa/Data/NoHuman/D2_R1_001.fastq.gz,/scratch/pawseyXXXX/youruser/proj/OpusTaxa/Data/NoHuman/D2_R2_001.fastq.gz,ILLUMINA
D3,D3,/scratch/pawseyXXXX/youruser/proj/OpusTaxa/Data/NoHuman/D3_R1_001.fastq.gz,/scratch/pawseyXXXX/youruser/proj/OpusTaxa/Data/NoHuman/D3_R2_001.fastq.gz,ILLUMINA
```

**Give each donor its own `group`.** Groups control co-abundance binning; one donor per group keeps donors completely independent, which is what you want when the MAGs become per-donor databases later.

### `assemblies.csv` — assemblies

```csv
id,group,assembler,fasta
D1,D1,SPAdes,/scratch/pawseyXXXX/youruser/proj/donor_MAGs/D1.scaffolds.fasta
D2,D2,SPAdes,/scratch/pawseyXXXX/youruser/proj/donor_MAGs/D2.scaffolds.fasta
D3,D3,SPAdes,/scratch/pawseyXXXX/youruser/proj/donor_MAGs/D3.scaffolds.fasta
```

| Column | Notes |
|---|---|
| `id` | Must match `sample` in the reads sheet |
| `group` | Must match the reads sheet |
| `assembler` | Must be one of `MEGAHIT`, `SPAdes`, `SPAdesHybrid`, `Flye`, `MetaMDBG`. **metaSPAdes output is `SPAdes`.** |
| `fasta` | `.fasta/.fa/.fna`, optionally `.gz`. Each path must be unique. |

> **Version note.** The `--input` schema changed at nf-core/mag **5.0.0**, which added the `short_reads_platform` column. The sheets above are for 5.x. On 4.x that column does not exist and will be rejected.

---

## Run

```bash
nextflow run nf-core/mag -r 5.4.2 \
    -profile singularity \
    -c nextflow.config \
    -resume \
    --input samplesheet.csv \
    --assembly_input assemblies.csv \
    --outdir results \
    --binning_map_mode own \
    --skip_concoct \
    --skip_comebin \
    --skip_metabinner \
    --semibin_environment human_gut \
    --refine_bins_dastool \
    --postbinning_input refined_bins_only \
    --run_checkm2 \
    --skip_gtdbtk
```

What the flags do:

| Flag | Why |
|---|---|
| `--assembly_input` | Use the step-1 assemblies. Assembly and read preprocessing are then skipped automatically — there is no `--skip_assembly` and you don't need one. |
| `--binning_map_mode own` | Map each donor's reads only to that donor's own assembly. The default (`group`) cross-maps within a group. |
| `--semibin_environment human_gut` | SemiBin2 has pre-trained models per environment; the gut model is the right one for faecal metagenomes. |
| `--refine_bins_dastool` | Run DAS Tool to reconcile MetaBAT2 and SemiBin2 into one refined, non-redundant set. Better bins than either binner alone. |
| `--postbinning_input refined_bins_only` | Send **only** the DAS Tool refined bins to downstream QC, rather than also carrying the raw per-binner sets. |
| `--run_checkm2` | Completeness and contamination — step 3. |
| `--skip_concoct`, `--skip_comebin`, `--skip_metabinner` | Disable the other binners. Fewer binners, faster run. |
| `--skip_gtdbtk` | Taxonomy is not needed: the MAGs are identified by which donor they came from, not by species name. Skipping saves a large database download and a lot of runtime. |
| `-resume` | Restart from cache after a failure. Have it from the first run. |

Run this from a persistent session on the workflow node — see [step 0](00-setup-setonix.md).

> **Read the resolved parameters Nextflow prints at launch.** Depending on version and profile, binners or refinement steps you assumed were off may still be on. Trust that block over this table.

---

## Output

```
results/
└── GenomeBinning/
    ├── MetaBAT2/bins/              # raw MetaBAT2 bins
    ├── SemiBin/                    # raw SemiBin2 bins
    ├── DASTool/                    # refined bins  ← the ones to use
    ├── QC/                         # CheckM2 report
    └── depths/                     # contig coverage used for binning
```

Bins are typically gzipped and named after the assembler, binner and sample — e.g. `SPAdes-MetaBAT2-D1.81.fa.gz`, where `D1` is the donor and `81` the bin number. That naming is what lets you split bins by donor in the next step.

Expect somewhere in the region of 50–150 MAGs per deeply sequenced donor faecal sample. Large differences in MAG count between donors will propagate straight into apparent engraftment differences, so note them now.

Next: **[Step 3 — Quality control](03-quality-control.md)**
