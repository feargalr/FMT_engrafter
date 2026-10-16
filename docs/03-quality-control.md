# Step 3 — Quality control: filtering the MAGs

Not every bin is a real genome. Before the donor MAGs become a reference database, filter out the ones that would mislead you.

CheckM2 estimates two things from single-copy marker genes:

- **Completeness** — how much of the organism's genome the bin captured
- **Contamination** — how much material looks like it came from something else

If you ran step 2 with `--run_checkm2`, the report is already there:

```bash
find results/GenomeBinning/QC -name 'quality_report.tsv'
head -1 results/GenomeBinning/QC/*/quality_report.tsv
```

Columns are `Name`, `Completeness`, `Contamination` in positions 1–3. Check that before trusting any `awk` below — the layout has shifted between CheckM2 versions.

---

## Why contamination matters more than completeness

These two do different jobs here, and it is worth being deliberate about the thresholds rather than copying the MIMAG defaults.

**Completeness can be relaxed.** A 60%-complete MAG still carries plenty of k-mers for sylph to detect. Less genome means a wider confidence interval on the ANI, not a wrong answer.

**Contamination cannot.** Contigs from another organism sitting inside your "donor MAG" will be detected in recipients who never received that organism — and will produce engraftment that looks real. This is the failure mode that quietly inflates your numbers.

So: filter contamination hard, completeness gently.

A reasonable starting point:

```
completeness ≥ 50   AND   contamination ≤ 5
```

Whatever you choose, apply it identically to every donor and record it in your methods. Different thresholds between donors create between-donor differences in engraftment rate that are purely technical.

---

## Running CheckM2 separately

Sometimes CheckM2 does not complete for every donor inside the pipeline run — a job times out, or you add a donor later. Running it standalone on the bins is straightforward, and is often quicker than re-running the pipeline.

A template is at [`scripts/run_checkm2.slurm`](../scripts/run_checkm2.slurm). The essentials:

```bash
# Bins are gzipped; CheckM2 wants plain FASTA
mkdir -p checkm2_manual/input_bins
for f in results/GenomeBinning/DASTool/*.fa.gz; do
    gzip -dc "$f" > "checkm2_manual/input_bins/$(basename "$f" .gz)"
done

singularity exec --bind /scratch:/scratch --bind /software:/software \
    "$CHECKM2_CONTAINER" \
    checkm2 predict \
        --input checkm2_manual/input_bins \
        --extension fa \
        --output-directory checkm2_manual/results \
        --threads "$SLURM_CPUS_PER_TASK" \
        --database_path "$CHECKM2_DB"
```

The CheckM2 database is a `.dmnd` DIAMOND file. If the pipeline already downloaded it, reuse that copy rather than fetching it again:

```bash
CHECKM2_DB=$(find -L "$NXF_WORK" -name '*.dmnd' -type f -print -quit)
```

If you end up combining a standalone report with the pipeline's, check the headers match first:

```bash
diff -q <(head -1 existing_report.tsv) <(head -1 new_report.tsv) \
    || { echo "Headers differ - do not concatenate"; exit 1; }
```

---

## Apply the filter and split by donor

This is the step that produces the per-donor MAG catalogues used in step 4. Each donor gets its own directory, because each donor gets its own sylph database.

```bash
CHECKM2=results/GenomeBinning/QC/quality_report.tsv
BINS=results/GenomeBinning/DASTool

MIN_COMP=50
MAX_CONT=5

mkdir -p MAG_catalogues

# Keep bins passing both thresholds, filing each under its donor.
awk -F'\t' -v min="$MIN_COMP" -v max="$MAX_CONT" \
    'NR>1 && $2>=min && $3<=max {print $1}' "$CHECKM2" |
while read -r bin; do
    # Bin names look like SPAdes-MetaBAT2-D1.81 - pull the donor out.
    donor=$(echo "$bin" | grep -oE 'D[0-9]+' | head -1)
    [ -n "$donor" ] || { echo "WARN: no donor in '$bin'" >&2; continue; }

    mkdir -p "MAG_catalogues/$donor"
    for ext in .fa.gz .fa .fasta; do
        if [ -s "$BINS/$bin$ext" ]; then
            cp "$BINS/$bin$ext" "MAG_catalogues/$donor/"
            break
        fi
    done
done

# How many MAGs did each donor contribute?
for d in MAG_catalogues/*/; do
    printf '%s\t%s\n' "$(basename "$d")" "$(ls "$d" | wc -l | tr -d ' ')"
done
```

Adjust the `grep -oE 'D[0-9]+'` pattern to match your own donor naming.

That per-donor count is worth writing down — it is the **denominator** for the engraftment percentage in step 5. A donor with 124 MAGs and a donor with 91 MAGs are not directly comparable on raw counts.

---

## Check before moving on

- **Every donor has a catalogue directory**, with a plausible number of MAGs in it.
- **Nothing with high contamination survived.** Spot-check:

```bash
awk -F'\t' 'NR>1 && $3>10 {print $1, "contamination:", $3}' "$CHECKM2"
```

- **Record the counts.** You need them in step 5.

Next: **[Step 4 — Sylph](04-sylph.md)**
