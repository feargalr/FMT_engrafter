# Step 4 — Sylph: matching samples against donor genomes

[sylph](https://github.com/bluenote-1577/sylph) profiles metagenomes by k-mer containment: sketch a subsample of k-mers from a set of reference genomes, sketch the same way from reads, then ask how much of each reference is contained in each sample. It is fast enough to profile a longitudinal cohort against custom references in minutes.

The references here are **your donor MAGs**. A public GTDB run would tell you "*Bacteroides uniformis* is present". This tells you "**the genome we assembled from donor D1** is present" — which is the actual question.

---

## One database per donor

Build a **separate sylph database for each donor**, then profile every sample against every donor database:

```
         D1.syldb      D2.syldb      D3.syldb
             ▲             ▲             ▲
             └─────────────┼─────────────┘
                           │
              every recipient sample sketch
```

For three donors and 28 samples that is 84 profile runs — still fast, and worth it for what it buys:

- **Provenance is exact.** A hit against `D1.syldb` is a hit against D1's genome. There is no ambiguity about which donor contributed it.
- **No dereplication needed.** Donors never share a database, so two donors carrying the same species never collide. sylph recommends dereplicating a database at 95% ANI for abundance accuracy, but that problem does not arise within a single donor's catalogue, and we are not using abundance anyway.
- **Cross-donor specificity is measurable.** Profiling a recipient against donors they did *not* receive gives you a built-in negative control. If a recipient matches their own donor's MAGs and not the other donors', the signal is real. If they match everyone equally, you are looking at species-level background, not engraftment.

That last point is worth setting up deliberately — it is the cheapest sanity check available here.

---

## Get sylph

OpusTaxa ships a sylph container, so there is nothing to install:

```bash
module load singularity/4.1.0-slurm
CONTAINER="oras://quay.io/yenkai_chen_id/opustaxa_sylph:0.0.2"
singularity exec "$CONTAINER" sylph --version
```

---

## Build the databases

One `.syldb` per donor, from that donor's quality-filtered MAGs:

```bash
mkdir -p sylph_databases

for donor_dir in MAG_catalogues/*/; do
    donor=$(basename "$donor_dir")
    singularity exec "$CONTAINER" \
        sylph sketch -g "$donor_dir"/*.fa.gz \
            -o "sylph_databases/$donor" \
            -c 200 \
            -t 16
done

ls -la sylph_databases/      # D1.syldb, D2.syldb, D3.syldb
```

- **`-g`** marks the inputs as *genomes* rather than samples. sylph infers FASTA→genome and FASTQ→sample, but be explicit.
- **`-c 200`** is the k-mer subsampling rate, and the default for genomes.

> **The one hard rule: the genome `-c` must be ≥ the read `-c`.** Both are set to 200 here, which satisfies it. If you lower one, lower the other, and keep the inequality.

---

## Sketch the reads

Sketch every sample you intend to profile — **all recipient timepoints including pre-FMT, and the donors themselves.**

Include the donors. Profiling a donor against its own database is the positive control: those MAGs came from that sample, so they must come back. If they don't, something is wrong with the database and you want to know now.

Build a manifest first — sample name, R1, R2, tab-separated:

```bash
mkdir -p sylph_tracking
for r1 in OpusTaxa/Data/NoHuman/*_R1_001.fastq.gz; do
    s=$(basename "$r1" _R1_001.fastq.gz)
    printf '%s\t%s\t%s\n' "$s" "$r1" "${r1/_R1_/_R2_}"
done > sylph_tracking/samples.tsv

wc -l < sylph_tracking/samples.tsv
```

---

## Sketch and profile as a job array

Sketching and profiling are per-sample and embarrassingly parallel, so a SLURM array is the natural fit. Full script at [`scripts/run_sylph.slurm`](../scripts/run_sylph.slurm); set `--array=1-N` to your sample count.

The core of it:

```bash
# One array task per sample
LINE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$MANIFEST")
IFS=$'\t' read -r SAMPLE R1 R2 <<< "$LINE"

# Step 1: sketch the reads (skip if already done - makes the job resumable)
SKETCH="${WORK}/sketches/${SAMPLE}.paired.sylsp"
if [[ ! -s "$SKETCH" ]]; then
    singularity exec "$CONTAINER" \
        sylph sketch -1 "$R1" -2 "$R2" \
            -S "$SAMPLE" -c 200 -t "$THREADS" \
            -d "${WORK}/sketches"
fi

# Step 2: profile against each donor database
for DONOR in D1 D2 D3; do
    OUT="${WORK}/profiles/${SAMPLE}_vs_${DONOR}.tsv"
    [[ -s "$OUT" ]] && continue          # resumable

    singularity exec "$CONTAINER" \
        sylph profile \
            "${DB_DIR}/${DONOR}.syldb" \
            "$SKETCH" \
            -t "$THREADS" \
            -m 95 \
            -o "$OUT"
done
```

`-m 95` (`--minimum-ani`) sets the reporting floor at 95% ANI. That is deliberately permissive — the strict 99.9% filter comes later, in step 5. Reporting down to 95% means the output also contains the same-species-different-strain hits, which are informative: they tell you the recipient carried a relative of that donor genome rather than nothing at all.

> Use the long option names (`--minimum-ani`, `--min-number-kmers`) where you can. There is a short-flag ambiguity around `-M` in recent sylph versions, and the published cookbook is stale on at least one default. Check with `sylph profile -h` on your installed version.

Submit:

```bash
sbatch --array=1-28%8 scripts/run_sylph.slurm
```

The `%8` caps concurrent tasks at 8 — polite on a shared queue, and plenty fast.

---

## Combine the profiles

Each run produces one TSV per sample×donor pair. Merge them into one table, adding `Sample` and `Donor_database` columns so you know what each row came from:

```bash
OUT=sylph_combined_profiles.tsv

first=1
for f in sylph_tracking/profiles/*_vs_*.tsv; do
    base=$(basename "$f" .tsv)
    sample="${base%_vs_*}"
    donor="${base##*_vs_}"

    if [[ $first -eq 1 ]]; then
        printf 'Sample\tDonor_database\t' > "$OUT"
        head -1 "$f" >> "$OUT"
        first=0
    fi
    tail -n +2 "$f" | awk -v s="$sample" -v d="$donor" \
        'BEGIN{OFS="\t"} {print s, d, $0}' >> "$OUT"
done

wc -l < "$OUT"
head -1 "$OUT"
```

The result has the two new columns followed by sylph's own:

```
Sample  Donor_database  Sample_file  Genome_file  Taxonomic_abundance
Sequence_abundance  Adjusted_ANI  Eff_cov  ANI_5-95_percentile  Eff_lambda
Lambda_5-95_percentile  Median_cov  Mean_cov_geq1  Containment_ind
Naive_ANI  kmers_reassigned  Contig_name
```

The two that matter for step 5 are **`Adjusted_ANI`** (column 7) and **`Eff_cov`** (column 8). `Genome_file` (column 4) identifies which MAG. The abundance columns are not used.

---

## Check the positive control

Before filtering, confirm each donor recovers its own MAGs:

```bash
awk -F'\t' 'NR>1 && $1==$2' sylph_combined_profiles.tsv | wc -l
```

(That works if your donor sample names match the database names; adjust otherwise.) You should see a large number of high-ANI, high-coverage hits. If a donor barely recovers its own genomes, stop and fix that before interpreting any recipient result.

Next: **[Step 5 — Filter and count](05-filter-and-count.md)**
