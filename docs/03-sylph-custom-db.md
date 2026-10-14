# Stage 3 — Building a custom sylph database

[sylph](https://github.com/bluenote-1577/sylph) profiles metagenomes by k-mer containment: it sketches a subsample of k-mers from a set of reference genomes, sketches the same way from your reads, and asks how much of each reference is contained in each sample. It is fast enough to profile a longitudinal cohort against a custom reference in minutes.

The whole point of this stage is that the reference is **your donor MAGs**, not a public database. A GTDB run tells you "*Bacteroides uniformis* is present". A donor-MAG run tells you "**`Donor_01_MAG017`** is present" — which is the actual question.

> Commands here are for **sylph v1.0.0**. Defaults changed in that release. Verify against your installed version with `sylph profile -h`.

---

## Get sylph

OpusTaxa already ships a sylph container, so there is nothing to install:

```bash
module load singularity/4.1.0-slurm
export SYLPH="singularity exec oras://quay.io/yenkai_chen_id/opustaxa_sylph:0.0.2 sylph"
$SYLPH --version
```

Every command below uses `$SYLPH`. If you have sylph on your `PATH` another way, just set `export SYLPH=sylph`.

> **Use the long option names** (`--min-number-kmers`, `--minimum-ani`) rather than short flags. There is a short-flag ambiguity around `-M` in recent versions, and the published cookbook is stale on at least one default. Long forms are unambiguous.

---

## Assemble the catalogue

Collect the MAGs that passed your stage-2 quality filter into one directory, renaming so that **every filename carries its donor of origin** and is unique across the whole catalogue:

```bash
cd $MYSCRATCH/FMT_engrafter
mkdir -p donor_MAG_catalogue
```

```
donor_MAG_catalogue/
├── Donor_01_MAG001.fa
├── Donor_01_MAG002.fa
├── Donor_02_MAG001.fa
└── Donor_03_MAG001.fa
```

The filename is the identifier you get back in the results — sylph reports the genome path in `Genome_file`. Encode the donor there and the whole downstream analysis becomes a join on that string.

This loop copies in every bin that passed your quality filter, renames it, and writes a metadata table alongside. Point `RESULTS` at your stage-2 output:

```bash
RESULTS=$MYSCRATCH/FMT_engrafter/donor_MAGs/results
BINS="$RESULTS/GenomeBinning/MetaBAT2/bins"
CHECKM2=$(find "$RESULTS/GenomeBinning/QC" -name quality_report.tsv | head -1)

MIN_COMP=50     # completeness floor
MAX_CONT=5      # contamination ceiling - the one that matters most

mkdir -p donor_MAG_catalogue
printf 'mag_id\tdonor_id\tcompleteness\tcontamination\tsource_bin\n' \
    > donor_MAG_catalogue/catalogue_metadata.tsv

awk -F'\t' -v OFS='\t' -v min="$MIN_COMP" -v max="$MAX_CONT" \
    'NR>1 && $2>=min && $3<=max {print $1,$2,$3}' "$CHECKM2" |
while IFS=$'\t' read -r bin comp cont; do
    # Find the FASTA (extension varies between versions).
    src=""
    for ext in fa fasta; do
        [ -s "$BINS/$bin.$ext" ] && { src="$BINS/$bin.$ext"; break; }
    done
    [ -n "$src" ] || { echo "WARN: no FASTA for bin $bin" >&2; continue; }

    # nf-core/mag names bins like <sample>.<n> (sometimes MetaBAT2-<sample>.<n>).
    # Derive the MAG id from the bin name so it is deterministic: re-running
    # this loop gives identical ids rather than renumbering everything.
    donor="${bin%%.*}"; donor="${donor##*-}"
    num="${bin##*.}"
    mag_id=$(printf '%s_MAG%03d' "$donor" "$num")

    cp "$src" "donor_MAG_catalogue/${mag_id}.fa"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mag_id" "$donor" "$comp" "$cont" "$bin" \
        >> donor_MAG_catalogue/catalogue_metadata.tsv
done

wc -l < donor_MAG_catalogue/catalogue_metadata.tsv   # MAGs kept (+1 header)
head -3 donor_MAG_catalogue/catalogue_metadata.tsv
```

The metadata table looks like:

| mag_id | donor_id | completeness | contamination | source_bin |
|---|---|---|---|---|
| `Donor_01_MAG001` | `Donor_01` | 98.1 | 0.8 | `Donor_01.1` |

Keep it. Stage 4 needs it to attribute hits to donors and to check whether a weak hit is just a poor MAG.

> CheckM2's report columns are `Name`, `Completeness`, `Contamination` in positions 1–3. Confirm with `head -1 "$CHECKM2"` before trusting the `awk` above — column order has shifted between CheckM2 versions.

---

## Do not dereplicate

sylph's documentation recommends dereplicating a reference database at **95% ANI (species level)** before building. It is worth understanding why that advice exists, because **it does not apply here.**

The reason sylph gives is *abundance accuracy*. When two near-identical genomes sit in the same database, k-mer reassignment cannot cleanly decide between them, and a single organism gets reported as two — so the species looks roughly twice as abundant as it is. Both genomes are still reported; the damage is to the abundance values, not to detection.

**This tutorial does not use abundance.** The readout is how many donor MAGs are detected, so the failure mode that motivates dereplication costs us nothing. Both genomes being reported is, if anything, the conservative outcome for presence/absence work.

Meanwhile dereplication has two real costs here.

**It destroys donor provenance.** If `Donor_01_MAG017` and `Donor_02_MAG009` are the same species at 99% ANI, dereplication keeps one and discards the other, and you can no longer say *which donor* contributed that strain. Provenance is the entire point of building a custom catalogue.

**It hides genuine near-identity, which is signal.** If two genomes really are both present at ~99.9% identity, that is something you want to see — particularly before FMT. A recipient carrying a strain near-identical to one of the donor's MAGs at baseline is the single most important thing to know when interpreting that MAG later: its post-FMT "engraftment" is ambiguous at best. Collapsing those two genomes into one representative throws that away and leaves you unable to tell the ambiguous calls from the clean ones.

So redundancy in the catalogue is not noise to be suppressed. Both genomes being reported is exactly the behaviour you want, and stage 4 uses it.

So: **keep the catalogue as it is.** One entry per MAG that passed stage-2 QC, donor encoded in every filename.

The one thing still worth removing is near-duplicate bins *within a single donor* — two bins from the same assembly that are the same organism. They carry no extra information and just inflate your denominator, which matters because the engraftment proportion is measured against the donor's catalogue size.

> **If you later add abundance to the analysis**, revisit this. At that point sylph's dereplication advice applies in full, and you will need the representative→source-MAG mapping to retain donor provenance.

---

## Build the database

Sketch the catalogue into a single `.syldb`:

```bash
cd $MYSCRATCH/FMT_engrafter

$SYLPH sketch -g donor_MAG_catalogue/*.fa \
    -o donor_catalogue \
    -c 200 \
    -t 16
```

This produces **`donor_catalogue.syldb`**.

- **`-g`** marks the inputs as *genomes* rather than samples. sylph infers FASTA→genome and FASTQ→sample, but be explicit.
- **`-c 200`** is the k-mer subsampling rate and the default for genomes. Lower is more sensitive and larger; `-c 100` is reasonable if your MAGs are fragmentary or you are chasing low-abundance strains.
- **`-k`** defaults to 31. Only 21 and 31 are supported.

> **The one hard rule: the genome `-c` must be ≥ the read `-c`.** The documented pairing is genomes at `-c 200`, reads at `-c 100`. Violate it and profiling fails or silently misbehaves. If you change one, change both and keep the inequality.

Building a catalogue of a few hundred MAGs takes minutes on a single node — a short interactive job or even the workflow node is fine.

---

## Sketch the reads

Sketch every sample you intend to profile: **all recipient timepoints including pre-FMT, and the donors themselves.**

Include the donors. Profiling a donor against its own catalogue is your positive control — those MAGs came from that sample, so they must come back at high ANI and good coverage. If they do not, something is wrong with the database and you want to find out now rather than in stage 4.

Use the **host-removed** reads from OpusTaxa:

```bash
mkdir -p sketches

for r1 in OpusTaxa/Data/NoHuman/*_R1_001.fastq.gz; do
    sample=$(basename "$r1" _R1_001.fastq.gz)
    r2="OpusTaxa/Data/NoHuman/${sample}_R2_001.fastq.gz"
    $SYLPH sketch -1 "$r1" -2 "$r2" -d sketches -S "$sample" -c 100 -t 16
done
```

This writes one `sketches/{sample}.paired.sylsp` per sample. Sketching is separated from profiling so that you can re-profile against a different database later without re-reading the FASTQs — useful when you revise the catalogue.

Sketching is quick, but for a large cohort put the loop in a batch job rather than running it on the workflow node:

```bash
cat > sketch.slurm <<'EOF'
#!/bin/bash --login
#SBATCH --account=PAWSEY_PROJECT_HERE
#SBATCH --partition=work
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=04:00:00

module load singularity/4.1.0-slurm
SYLPH="singularity exec oras://quay.io/yenkai_chen_id/opustaxa_sylph:0.0.2 sylph"

mkdir -p sketches
for r1 in OpusTaxa/Data/NoHuman/*_R1_001.fastq.gz; do
    sample=$(basename "$r1" _R1_001.fastq.gz)
    [ -s "sketches/${sample}.paired.sylsp" ] && continue   # resumable
    $SYLPH sketch -1 "$r1" -2 "OpusTaxa/Data/NoHuman/${sample}_R2_001.fastq.gz" \
        -d sketches -S "$sample" -c 100 -t "$SLURM_CPUS_PER_TASK"
done
EOF

sed -i "s/PAWSEY_PROJECT_HERE/$PAWSEY_PROJECT/" sketch.slurm
sbatch sketch.slurm
```

The `[ -s ... ] && continue` line makes it resumable — if the job hits its walltime, resubmit and it picks up where it stopped.

> **Same reads, every sample.** Every sample must go through identical preprocessing. Profiling donors from host-removed reads and recipients from raw reads would make detection asymmetric and the comparison meaningless.

---

## Check the database

Before moving on, profile one donor against the catalogue and confirm its own MAGs come back:

```bash
$SYLPH profile donor_catalogue.syldb sketches/Donor_01.paired.sylsp \
    -t 16 -o check_Donor_01.tsv

cut -f2,5,6 check_Donor_01.tsv | head
```

You should see `Donor_01_MAG*` entries with `Adjusted_ANI` near 100 and healthy coverage. If a donor's own MAGs are missing or come back at low ANI, stop and fix it — the catalogue is built from that very sample, so anything else means a naming, path or parameter problem.

Next: **[Stage 4 — Engraftment analysis](04-engraftment-analysis.md)**
