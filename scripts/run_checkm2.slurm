#!/bin/bash
#SBATCH --job-name=checkm2_FMT
#SBATCH --account=pawseyXXXX
#SBATCH --partition=work
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=checkm2_%j.out
#SBATCH --error=checkm2_%j.err
#
# Run CheckM2 on bins outside the nf-core/mag pipeline.
#
# Useful when CheckM2 did not finish for every donor inside the pipeline run,
# or when donors were added later - re-running the whole pipeline to get a
# quality report is slow.
#
# Edit BASE, the account, and the container path before running.

set -euo pipefail

module load singularity/4.1.0-slurm

# ---------------------------------------------------------------- config --

BASE="/scratch/pawseyXXXX/youruser/myproject/donor_MAGs"

BINS="${BASE}/results/GenomeBinning/DASTool"
OUT="${BASE}/checkm2_manual"
INPUT="${OUT}/input_bins"
RESULTS="${OUT}/results"

# The CheckM2 image nf-core/mag already pulled. Find it with:
#   find /software/projects/pawseyXXXX/youruser/.nextflow_singularity -name '*checkm2*'
CONTAINER="/software/projects/pawseyXXXX/youruser/.nextflow_singularity/checkm2.img"

# Reuse the database the pipeline downloaded rather than fetching it again.
DB_SEARCH="/scratch/pawseyXXXX/youruser/myproject/nxf_work"

mkdir -p "$INPUT" "$RESULTS"

# ------------------------------------------------------- locate database --

DB=$(find -L "$DB_SEARCH" -name '*.dmnd' -type f -print -quit)

if [[ -z "$DB" ]]; then
    echo "ERROR: CheckM2 database (.dmnd) not found under $DB_SEARCH" >&2
    exit 1
fi
echo "CheckM2 database: $DB"

# ----------------------------------------------------------- prepare bins --
#
# Bins are gzipped; CheckM2 wants plain FASTA.

echo "Preparing MAGs..."
for file in "$BINS"/*.fa.gz; do
    [[ -e "$file" ]] || continue
    gzip -dc "$file" > "${INPUT}/$(basename "$file" .gz)"
done

N=$(find "$INPUT" -maxdepth 1 -name '*.fa' | wc -l)
echo "MAGs prepared: $N"
[[ "$N" -gt 0 ]] || { echo "ERROR: no bins found in $BINS" >&2; exit 1; }

# ------------------------------------------------------------ run CheckM2 --

echo "Starting CheckM2..."
date

singularity exec \
    --bind /scratch:/scratch \
    --bind /software:/software \
    "$CONTAINER" \
    checkm2 predict \
        --input "$INPUT" \
        --extension fa \
        --output-directory "$RESULTS" \
        --threads "$SLURM_CPUS_PER_TASK" \
        --database_path "$DB"

echo "CheckM2 completed."
date

# -------------------------------------------------------------- summarise --

REPORT="${RESULTS}/quality_report.tsv"

echo
echo "MAGs assessed per donor:"
tail -n +2 "$REPORT" | cut -f1 | grep -oE 'D[0-9]+' | sort | uniq -c

echo
echo "MAGs exceeding 10% contamination (review these):"
awk -F'\t' 'NR>1 && $3>10 { print $1, "completeness:", $2, "contamination:", $3 }' "$REPORT"

echo
echo "Report: $REPORT"

# If combining with a report from the pipeline run, check headers match first:
#
#   diff -q <(head -1 "$EXISTING") <(head -1 "$REPORT") \
#       || { echo "Headers differ - not combining"; exit 1; }
#   { head -1 "$EXISTING"; tail -n +2 "$EXISTING"; tail -n +2 "$REPORT"; } > combined.tsv
