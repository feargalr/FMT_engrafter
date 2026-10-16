# Step 5 — Filter and count

The combined profile table has every hit sylph reported down to 95% ANI. Now apply the strict thresholds and count.

---

## The thresholds

```
Adjusted_ANI ≥ 99.9    AND    Eff_cov ≥ 1
```

**ANI ≥ 99.9%** is the strain-identity criterion. Below that you are looking at a relative of the donor genome, not the donor genome.

**Coverage ≥ 1×** is the detection floor, and it is doing more work than it looks. sylph will report a genome from as little as 0.01–0.05× coverage, and an ANI computed off a handful of k-mers is unstable however high the number looks. Requiring a full 1× means the hit is supported by real depth across the genome. This is deliberately strict — it trades sensitivity for calls you can defend.

Both must hold. A high-ANI hit at 0.1× coverage does not count; neither does a 20× hit at 98.5% ANI.

> A worked example from a real row: `Adjusted_ANI 98.45, Eff_cov 20.0`. Plenty of depth, but 1.5% divergent — the recipient carries a *different strain of the same species*. Correctly excluded.

---

## Count per sample and donor

The counting is a filter plus a deduplicated count. A `.tsv` of samples and the combined profiles are the only inputs. Full script at [`scripts/format_results.sh`](../scripts/format_results.sh).

```bash
MIN_ANI=99.9
MIN_COV=1

awk -F'\t' -v min_ani="$MIN_ANI" -v min_cov="$MIN_COV" '
BEGIN { OFS="\t" }
NR==1 { next }
{
    sample = $1        # Sample
    db     = $2        # Donor_database
    mag    = $4        # Genome_file
    ani    = $7        # Adjusted_ANI
    cov    = $8        # Eff_cov

    if (ani != "NA" && cov != "NA" && ani+0 >= min_ani && cov+0 >= min_cov) {
        # Key on sample+donor+MAG so a MAG is never counted twice
        hits[sample SUBSEP db SUBSEP mag] = 1
    }
}
END {
    for (k in hits) {
        split(k, a, SUBSEP)
        counts[a[1] SUBSEP a[2]]++
    }
    for (c in counts) {
        split(c, a, SUBSEP)
        print a[1], a[2], counts[c]
    }
}' sylph_combined_profiles.tsv |
sort -t $'\t' -k1,1 -k2,2 |
{ printf 'Sample\tDonor\tMAGs_detected\n'; cat; } > sylph_MAG_counts.tsv
```

**The deduplication matters.** sylph can report the same genome more than once across rows; keying on `sample+donor+MAG` before counting stops a single MAG inflating the total.

A sample×donor pair with no surviving hits produces no row at all — so if you want explicit zeros, generate the full grid from your sample manifest and join the counts onto it. The script in `scripts/` does this, which is why its output has a row for every pair.

---

## Reshape to one row per sample

With one database per donor, the natural layout is donors as columns:

```bash
awk -F'\t' '
BEGIN { OFS="\t" }
NR==1 { next }
{ samples[$1]=1; counts[$1 SUBSEP $2]=$3 }
END {
    for (s in samples)
        print s, counts[s SUBSEP "D1"]+0, counts[s SUBSEP "D2"]+0, counts[s SUBSEP "D3"]+0
}' sylph_MAG_counts.tsv |
sort -t $'\t' -k1,1 |
{ printf 'Sample\tD1\tD2\tD3\n'; cat; } > sylph_MAG_counts_wide.tsv

column -t sylph_MAG_counts_wide.tsv
```

```
Sample        D1   D2   D3
Sample_001    0    0    0
Sample_002    0    1    0
Sample_003    0    1    0
Sample_004    0    0    0
```

**Read this table across rows, not just down columns.** Each recipient should light up against *their own* donor and stay near zero against the others. A sample with similar counts against all three donors is showing you species-level background, not engraftment — that is the cross-donor negative control from step 4 doing its job.

### The counts are usually bimodal, and that is the point

Plot or tabulate the distribution of non-zero counts and you will typically see two clearly separated groups:

```bash
awk -F'\t' 'NR>1 && $3>0 {print $3}' sylph_MAG_counts.tsv | sort -n | uniq -c
```

```
   6 samples with   1 MAG
   2 samples with   2 MAGs
   1 sample  with   3 MAGs
   ...                          ← background
   1 sample  with  31 MAGs
   1 sample  with  54 MAGs
   1 sample  with 111 MAGs      ← engraftment
```

Counts of **one to a handful** are background: a few donor MAGs are common gut organisms, and any recipient will match a couple of them at ≥99.9% by chance. Counts in the **tens to over a hundred** are a different phenomenon — that is a substantial fraction of a donor's catalogue arriving together, which is what engraftment looks like.

The gap between the two groups is your real evidence, and it is more convincing than any single threshold. A sample matching its own donor with 50 MAGs while matching other donors with 1 is unambiguous. If your data has no such gap — everything in the 1–5 range — then you are looking at background across the board and should say so, rather than reporting the largest number as a result.

This is also why the cross-donor comparison is worth the extra compute: the non-matching donors give you the background distribution directly, measured in your own samples rather than assumed.

---

## Add the denominator

A raw count is not comparable between donors, because donors contribute different numbers of MAGs. Divide by the donor's catalogue size:

```bash
# Catalogue sizes from step 3
for d in MAG_catalogues/*/; do
    printf '%s\t%s\n' "$(basename "$d")" "$(ls "$d" | wc -l | tr -d ' ')"
done > donor_mag_totals.tsv

awk -F'\t' 'BEGIN{OFS="\t"}
    NR==FNR { total[$1]=$2; next }
    FNR==1  { print $0, "Total_donor_MAGs", "Percent"; next }
    { t = total[$2]+0
      print $0, t, (t ? sprintf("%.2f", 100*$3/t) : "NA") }
' donor_mag_totals.tsv sylph_MAG_counts.tsv > sylph_MAG_percent.tsv

column -t sylph_MAG_percent.tsv | head
```

Join that to your sample metadata — participant, donor received, timepoint — and you have the final result:

| Participant | Donor | Timepoint | MAGs shared | Donor MAGs total | % |
|---|---|---|---|---|---|
| RecipA | D2 | baseline | 1 | 108 | 0.93 |
| RecipA | D2 | post-FMT 1 | 34 | 108 | 31.48 |
| RecipA | D2 | post-FMT 2 | 29 | 108 | 26.85 |
| RecipB | D1 | baseline | 0 | 86 | 0.00 |
| RecipB | D1 | post-FMT 1 | 2 | 86 | 2.33 |
| RecipB | D1 | post-FMT 2 | 1 | 86 | 1.16 |

RecipA engrafted: a third of the donor's catalogue, sustained across both timepoints, on a baseline of one. RecipB did not: counts of 1–2 are in the range you would expect by chance from shared gut species, and there is no separation from baseline worth reporting as engraftment.

Always report the count and the denominator, not just the percentage. "5 of 124" is interpretable; "4.03%" on its own hides that the denominator depends on how deeply that donor was sequenced.

---

## Reading the result

**Baseline should be at or near zero.** That is the single most important check. The pre-FMT sample is the same recipient, the same thresholds, the same database — so a non-zero baseline means the recipient already carried something matching the donor's genomes at ≥99.9% ANI and ≥1× coverage. A small non-zero baseline is normal (donors and recipients share a species pool); a large one means the engraftment numbers above it are not attributable to the FMT.

**Subtract the baseline where it is non-zero.** If a recipient starts at 1 and reaches 9, the engraftment signal is 8, not 9.

**A rise that persists is stronger than a rise that spikes.** A MAG count that goes up at the first post-FMT timepoint and falls back is transient detection — delivered but not established. Persistence at a later timepoint is the stronger claim.

**Zero is a real result.** A recipient with no donor MAGs at any post-FMT timepoint is informative, not a failed analysis. Check their sequencing depth before concluding anything, but failed engraftment happens and is worth reporting.

---

## Check the thresholds hold up

Both numbers are analytical choices. Re-run the count across a range and see whether the conclusions move:

```bash
for ani in 99.0 99.5 99.9 99.95; do
    for cov in 0.5 1 2; do
        n=$(awk -F'\t' -v a="$ani" -v c="$cov" '
            NR>1 && $7!="NA" && $8!="NA" && $7+0>=a && $8+0>=c {
                print $1 SUBSEP $2 SUBSEP $4
            }' sylph_combined_profiles.tsv | sort -u | wc -l)
        printf 'ANI>=%s cov>=%s\t%s hits\n' "$ani" "$cov" "$n"
    done
done
```

If the baseline stays near zero and the post-FMT counts stay clearly above it across that grid, the result is robust to the thresholds. If the separation only appears at one specific combination, say so when you report it.

---

See [what engraftment means](concepts/engraftment.md) for how to interpret — and how not to overstate — a count like this.
