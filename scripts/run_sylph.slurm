#!/bin/bash
#SBATCH --job-name=sylph_FMT
#SBATCH --account=pawseyXXXX
#SBATCH --partition=work
#SBATCH --array=1-28%8
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/sylph_%A_%a.out
#SBATCH --error=logs/sylph_%A_%a.err
#
# Sketch one sample's reads, then profile it against every donor database.
#
# One array task per sample. Set --array=1-N to your sample count; %8 caps
# concurrent tasks. Both stages skip work that is already done, so if the job
# times out you can simply resubmit.
#
#   sbatch --array=1-28%8 scripts/run_sylph.slurm
#
# Edit BASE, DONORS and the account above before running.

set -euo pipefail

module load singularity/4.1.0-slurm

# ---------------------------------------------------------------- config --

BASE="/scratch/pawseyXXXX/youruser/myproject"

WORK="${BASE}/sylph_tracking"
MANIFEST="${WORK}/samples.tsv"          # sample <TAB> R1 <TAB> R2
DB_DIR="${BASE}/donor_MAGs/sylph_databases"

CONTAINER="oras://quay.io/yenkai_chen_id/opustaxa_sylph:0.0.2"

DONORS=(D1 D2 D3)                       # one .syldb per donor

THREADS="${SLURM_CPUS_PER_TASK}"

mkdir -p "${WORK}/sketches" "${WORK}/profiles"

# ----------------------------------------------------- sample for this task --

LINE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$MANIFEST")
IFS=$'\t' read -r SAMPLE R1 R2 <<< "$LINE"

if [[ -z "${SAMPLE:-}" || ! -s "$R1" || ! -s "$R2" ]]; then
    echo "ERROR: missing sample or input FASTQs for array index ${SLURM_ARRAY_TASK_ID}" >&2
    exit 1
fi

echo "======================================"
echo "Sample: ${SAMPLE}"
echo "R1: ${R1}"
echo "R2: ${R2}"
echo "======================================"

# --------------------------------------------------- 1. sketch the reads --
#
# -c 200 must be <= the -c used when sketching the donor genomes.

SKETCH="${WORK}/sketches/${SAMPLE}.paired.sylsp"

if [[ ! -s "$SKETCH" ]]; then
    echo "Sketching ${SAMPLE}"
    singularity exec "$CONTAINER" \
        sylph sketch \
            -1 "$R1" \
            -2 "$R2" \
            -S "$SAMPLE" \
            -c 200 \
            -t "$THREADS" \
            -d "${WORK}/sketches"
fi

if [[ ! -s "$SKETCH" ]]; then
    echo "ERROR: sketch not generated: $SKETCH" >&2
    exit 1
fi

# ------------------------------------------ 2. profile against each donor --
#
# -m 95 reports hits down to 95% ANI. That is deliberately permissive: the
# strict 99.9% / 1x filter is applied later, and the looser output also shows
# same-species-different-strain hits, which are informative.

for DONOR in "${DONORS[@]}"; do
    DB="${DB_DIR}/${DONOR}.syldb"
    OUT="${WORK}/profiles/${SAMPLE}_vs_${DONOR}.tsv"

    if [[ -s "$OUT" ]]; then
        echo "Already completed: $OUT"
        continue
    fi

    if [[ ! -s "$DB" ]]; then
        echo "ERROR: missing database $DB" >&2
        exit 1
    fi

    echo "Profiling ${SAMPLE} against ${DONOR}"
    singularity exec "$CONTAINER" \
        sylph profile \
            "$DB" \
            "$SKETCH" \
            -t "$THREADS" \
            -m 95 \
            -o "$OUT"
done

echo "Completed ${SAMPLE}"
