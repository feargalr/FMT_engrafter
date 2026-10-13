# Stage 2 — nf-core/mag: binning donor genomes

A metagenomic assembly is a pile of thousands of contigs from hundreds of organisms, with nothing marking which contig came from which genome. **Binning** groups contigs that look like they came from the same organism, using sequence composition and coverage across samples. Each resulting bin is a **metagenome-assembled genome (MAG)** — an estimate of one microbial genome.

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

We use [nf-core/mag](https://nf-co.re/mag) and feed it the assemblies OpusTaxa already produced, rather than assembling a second time.

> **Versions here are from nf-core/mag 5.5.0.** The `--input` samplesheet schema changed in a breaking way at **5.0.0** (two platform columns were added). If you pin an older version, check `assets/schema_input.json` for that tag — the 4.x schema will reject the samplesheet below.

---

## Which samples to bin

**Bin the donor samples.** The donor MAGs are the reference catalogue that everything downstream is matched against.

You do *not* need to bin the recipients. Stage 4 profiles recipient **reads** directly against the donor catalogue, which is much cheaper than assembling and binning every recipient timepoint — the main reason this design scales to longitudinal cohorts.

**Bin each donor separately.** Do not co-assemble or co-bin donors together. Keeping donors separate preserves the donor→MAG mapping, which is what lets you say *which* donor contributed a given strain. Lose that and you can only say "some donor".

---

## Set up

```bash
cd $MYSCRATCH/FMT_engrafter
mkdir -p donor_MAGs && cd donor_MAGs

module load nextflow/25.04.6
module load singularity/4.1.0-slurm

export PAWSEY_PROJECT=pawseyXXXX     # if not already in ~/.bashrc
nextflow -version
```

Test the pipeline on its bundled dataset before using your own:

```bash
nextflow run nf-core/mag -r 5.5.0 \
    -profile test,singularity,pawsey_setonix \
    --outdir test_results
```

If that completes, your Nextflow/Singularity/SLURM chain works and any later failure is about your inputs.

---

## The Pawsey profile

nf-core ships an institutional config for Setonix. Use it rather than hand-writing an executor block:

```
-profile singularity,pawsey_setonix
```

It sets the SLURM executor, caps resources at 64 CPUs / 230 GB, selects the `work` queue (or `highmem` above 230 GB), loads `singularity/4.1.0-slurm`, and sets `cache = 'lenient'` and `stageInMode = 'symlink'` — both needed for `-resume` to work on Lustre.

Critically, it builds the account flag as `--account=$PAWSEY_PROJECT`. **If `PAWSEY_PROJECT` is unset, every job submits with an empty account and fails.**

You still want a small config of your own, mainly to put the work directory in the right place. Paste this:

```bash
cat > nextflow.config <<'EOF'
// Work dir MUST be on scratch - Nextflow work dirs are enormous and will
// exhaust a $HOME quota immediately.
workDir = "${System.getenv('MYSCRATCH')}/nxf_work"

params {
    max_cpus   = 64
    max_memory = '230.GB'
}

singularity {
    // Let containers see bind-mounted /scratch paths.
    envWhitelist = 'SINGULARITY_BINDPATH, SINGULARITYENV_LD_LIBRARY_PATH, SINGULARITYENV_LD_PRELOAD'
}

// Keep a record of what each run actually did.
timeline.enabled = true
report.enabled   = true
trace.enabled    = true
EOF
```

Scratch is purged after 21 days of inactivity, so publish anything you need out of `--outdir` before then.

---

## The two samplesheets

This is where most runs fail. You need **two** CSVs, and their identifiers must line up.

### 1. Reads — `samplesheet.csv`

Reads are **still required** even though you are supplying assemblies: nf-core/mag maps them back to the contigs to get the coverage signal that binning depends on.

Use the **host-removed** reads from OpusTaxa (`Data/NoHuman/`), not the raw ones. When `--assembly_input` is set, the pipeline bypasses its own adapter clipping and host removal, so whatever you supply is used as-is.

```csv
sample,group,short_reads_1,short_reads_2,short_reads_platform
Donor_01,0,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/NoHuman/Donor_01_R1_001.fastq.gz,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/NoHuman/Donor_01_R2_001.fastq.gz,ILLUMINA
Donor_02,0,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/NoHuman/Donor_02_R1_001.fastq.gz,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/NoHuman/Donor_02_R2_001.fastq.gz,ILLUMINA
Donor_03,0,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/NoHuman/Donor_03_R1_001.fastq.gz,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/NoHuman/Donor_03_R2_001.fastq.gz,ILLUMINA
```

Column notes:

| Column | Notes |
|---|---|
| `sample` | Required. Must match `id` in the assembly sheet. |
| `group` | Required. Used for co-abundance grouping. Keep all donors in group `0` with `--binning_map_mode own` (below). |
| `short_reads_1` / `_2` | Must be **gzipped** FASTQ — the schema enforces `\.f(ast)?q\.gz$`. Absolute paths. |
| `short_reads_platform` | Required whenever `short_reads_1` is set. Use `ILLUMINA`. **This column does not exist before v5.0.0.** |

`sample` + `run` must be unique together.

### 2. Assemblies — `assemblies.csv`

```csv
id,group,assembler,fasta
Donor_01,0,SPAdes,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/MetaSPAdes/Donor_01/scaffolds.fasta
Donor_02,0,SPAdes,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/MetaSPAdes/Donor_02/scaffolds.fasta
Donor_03,0,SPAdes,/scratch/pawseyXXXX/you/FMT_engrafter/OpusTaxa/Data/MetaSPAdes/Donor_03/scaffolds.fasta
```

| Column | Notes |
|---|---|
| `id` | Required. **Must equal `sample` in the reads sheet** for per-sample assemblies. |
| `group` | Required. Must match the reads sheet. |
| `assembler` | Required. One of `MEGAHIT`, `SPAdes`, `SPAdesHybrid`, `Flye`, `MetaMDBG`. **metaSPAdes output is `SPAdes`.** |
| `fasta` | Required. `.fasta/.fas/.fa/.fna`, optionally `.gz`. Each path must be unique across the sheet. |

### Generating both sheets

Typing absolute paths by hand is tedious and error-prone. This loop writes both sheets for whichever donors you name — edit the `OPUSTAXA` path and the donor list:

```bash
OPUSTAXA=$MYSCRATCH/FMT_engrafter/OpusTaxa

echo "sample,group,short_reads_1,short_reads_2,short_reads_platform" > samplesheet.csv
echo "id,group,assembler,fasta" > assemblies.csv

# List your donors literally here (a quoted "$DONORS" variable does not
# word-split under zsh, so a literal list is the portable form).
for s in Donor_01 Donor_02 Donor_03; do
    r1="$OPUSTAXA/Data/NoHuman/${s}_R1_001.fastq.gz"
    r2="$OPUSTAXA/Data/NoHuman/${s}_R2_001.fastq.gz"
    fa="$OPUSTAXA/Data/MetaSPAdes/${s}/scaffolds.fasta"

    # Skip anything incomplete rather than writing a broken row.
    for f in "$r1" "$r2" "$fa"; do
        [ -s "$f" ] || { echo "WARN: $s missing $f - skipping" >&2; continue 2; }
    done

    echo "${s},0,${r1},${r2},ILLUMINA" >> samplesheet.csv
    echo "${s},0,SPAdes,${fa}"         >> assemblies.csv
done

column -t -s, samplesheet.csv   # eyeball the result
column -t -s, assemblies.csv
```

Check the paths it printed actually exist before running the pipeline. A typo here surfaces as a confusing Nextflow schema error several minutes into the run.

> **Why `scaffolds.fasta` and not `contigs.fasta`?** metaSPAdes scaffolds join contigs across gaps using paired-end information, giving longer sequences and generally better bins. Either works — just be consistent, and record which you used.

---

## Run binning

```bash
nextflow run nf-core/mag -r 5.5.0 \
    -profile singularity,pawsey_setonix \
    -c nextflow.config \
    --input samplesheet.csv \
    --assembly_input assemblies.csv \
    --outdir results \
    --binning_map_mode own \
    --run_checkm2 \
    --skip_concoct \
    --skip_comebin \
    --skip_metabinner \
    --skip_gtdbtk \
    -resume
```

What the flags do:

- **`--assembly_input`** — supplies the pre-computed assemblies. Assembly and read preprocessing are then skipped automatically; there is no `--skip_assembly` flag and you do not need one.
- **`--binning_map_mode own`** — map each donor's reads only against that donor's own assembly. The default is `group`, which cross-maps every sample in a group. `own` is what keeps donors independent.
- **`--run_checkm2`** — bin quality estimation (see below).
- **`--skip_*`** — disables the alternative binners, leaving MetaBAT2. Fewer binners means a simpler, faster run; drop these flags if you want an ensemble.
- **`-resume`** — restarts from cached results after a failure. Worth having from the first run.

> **Check what actually ran.** Nextflow prints the resolved parameters at launch. Depending on version and profile, binners or refinement steps you assumed were off may still be enabled. Read that block rather than trusting the command above to produce a MetaBAT2-only run.

Run this in your `screen` session on the workflow node, not under `sbatch`.

---

## MAG quality with CheckM2

Not every bin is a real genome. CheckM2 estimates two things from single-copy marker genes:

- **Completeness** — how much of the organism's genome the bin captured
- **Contamination** — how much material looks like it came from something else

| MAG | Completeness | Contamination | Verdict |
|---|---|---|---|
| `MAG_001` | 98% | 1% | High quality |
| `MAG_002` | 91% | 3% | Good |
| `MAG_003` | 65% | 2% | Partial — usable for tracking |
| `MAG_004` | 42% | 8% | Drop |

*(Illustrative values.)*

The usual MIMAG convention is high-quality ≥90% complete / ≤5% contaminated, medium-quality ≥50% / ≤10%.

**For strain tracking, completeness and contamination do different jobs.** A 60%-complete MAG still carries plenty of k-mers to be detectable in stage 4 — less genome to match against means wider confidence intervals, not a wrong answer. **Contamination is the real problem**: contigs from another organism inside your "donor MAG" will be detected in recipients that never received that organism, producing false engraftment. Filter contamination hard; filter completeness gently.

A reasonable starting filter:

```
completeness >= 50  AND  contamination <= 5
```

Record the values for every MAG whatever you choose, apply the same filter to every donor, and state it in your methods. Inconsistent filtering across donors is a silent source of between-donor differences in engraftment rate.

> CheckM2 needs its reference database. nf-core/mag can download it, or you can point at a pre-existing copy with `--checkm2_db`. On Setonix, a shared copy under `/software/projects/$PAWSEY_PROJECT/` avoids every user re-downloading it.

---

## Output

```
results/
├── Assembly/                        # QUAST stats on the input assemblies
├── GenomeBinning/
│   ├── MetaBAT2/bins/               # the MAGs, per sample
│   │   ├── Donor_01.1.fa
│   │   ├── Donor_01.2.fa
│   │   └── ...
│   ├── QC/CheckM2/                  # completeness / contamination table
│   └── depths/                      # contig coverage used for binning
└── multiqc/
```

The MetaBAT2 bins plus the CheckM2 table are what stage 3 consumes.

---

## Check before moving on

- **Bins per donor.** A donor yielding only a handful of bins usually means a poor assembly — go back and check its read depth and host fraction from stage 1. A donor with few MAGs contributes little to the catalogue and will look like a poor engrafter for purely technical reasons.
- **The CheckM2 table exists and covers every bin.**
- **Bin counts are broadly comparable across donors.** Large differences in catalogue size between donors will propagate directly into apparent engraftment differences in stage 4.

Next: **[Stage 3 — Custom sylph database](03-sylph-custom-db.md)**
