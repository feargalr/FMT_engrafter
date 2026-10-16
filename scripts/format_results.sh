#!/bin/bash
#
# Filter sylph profiles and count donor MAGs detected per sample.
#
#   usage: scripts/format_results.sh [combined_profiles.tsv] [samples.tsv]
#
# Produces a long table (one row per sample x donor, zeros included) and a
# wide table (one row per sample, donors as columns).
#
# A MAG counts as detected when Adjusted_ANI >= 99.9 AND Eff_cov >= 1.
# Both are required: a high-ANI hit at trace coverage is not evidence.

set -euo pipefail

PROFILES="${1:-sylph_combined_profiles.tsv}"
SAMPLES="${2:-samples.tsv}"

LONG="sylph_MAG_counts_long.tsv"
WIDE="sylph_MAG_counts_wide.tsv"

MIN_ANI=99.9
MIN_COV=1

DONORS=(D1 D2 D3)

for f in "$PROFILES" "$SAMPLES"; do
    [[ -s "$f" ]] || { echo "ERROR: missing or empty input: $f" >&2; exit 1; }
done

# -------------------------------------------------------------- long form --
#
# Reads the sample manifest first so every sample x donor pair gets a row,
# including the zeros (sylph emits no row at all for an undetected genome).

awk -F'\t' \
    -v min_ani="$MIN_ANI" \
    -v min_cov="$MIN_COV" \
    -v donors="${DONORS[*]}" '
BEGIN {
    OFS = "\t"
    n_donors = split(donors, donor, " ")
}

# First file: sample manifest (sample is field 1)
FILENAME == ARGV[1] {
    if ($1 != "") samples[$1] = 1
    next
}

# Second file: combined sylph profiles
FNR == 1 { next }
{
    sample = $1        # Sample
    db     = $2        # Donor_database
    mag    = $4        # Genome_file
    ani    = $7        # Adjusted_ANI
    cov    = $8        # Eff_cov

    if (ani != "NA" && cov != "NA" && ani+0 >= min_ani && cov+0 >= min_cov) {
        # Key on sample+donor+MAG so a MAG is never double-counted
        hits[sample SUBSEP db SUBSEP mag] = 1
    }
}

END {
    for (k in hits) {
        split(k, a, SUBSEP)
        counts[a[1] SUBSEP a[2]]++
    }
    for (s in samples)
        for (i = 1; i <= n_donors; i++)
            print s, donor[i], counts[s SUBSEP donor[i]] + 0
}' "$SAMPLES" "$PROFILES" |
sort -t $'\t' -k1,1 -k2,2 |
{ printf 'Sample\tDonor\tMAGs_detected\n'; cat; } > "$LONG"

# -------------------------------------------------------------- wide form --

awk -F'\t' -v donors="${DONORS[*]}" '
BEGIN { OFS="\t"; n = split(donors, donor, " ") }
NR == 1 { next }
{ samples[$1] = 1; counts[$1 SUBSEP $2] = $3 }
END {
    for (s in samples) {
        line = s
        for (i = 1; i <= n; i++) line = line OFS (counts[s SUBSEP donor[i]] + 0)
        print line
    }
}' "$LONG" |
sort -t $'\t' -k1,1 |
{ printf 'Sample'; printf '\t%s' "${DONORS[@]}"; printf '\n'; cat; } > "$WIDE"

# ------------------------------------------------------------------ done --

echo "Donor MAG detection summary complete."
echo "Thresholds: ANI >= ${MIN_ANI}%, coverage >= ${MIN_COV}x"
echo
echo "  long: $LONG"
echo "  wide: $WIDE"
echo
echo "Samples:            $(( $(wc -l < "$WIDE") - 1 ))"
echo "Sample/donor pairs: $(( $(wc -l < "$LONG") - 1 ))"
