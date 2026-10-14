# Stage 4 — Profiling and calling engraftment

Everything is now in place: a donor MAG catalogue as a `.syldb`, and a read sketch per sample. This stage profiles every sample against the catalogue and turns the result into engraftment calls.

---

## Profile every sample at once

```bash
cd $MYSCRATCH/FMT_engrafter

$SYLPH profile donor_catalogue.syldb sketches/*.sylsp \
    -t 32 \
    --minimum-ani 95 \
    -o sylph_profiles.tsv
```

One command, every sample, one table. Doing it in a single pass is not just convenient — it guarantees identical settings for donors, pre-FMT and post-FMT samples, so detection is symmetric. Profiling sample groups separately with different flags is a reliable way to manufacture engraftment.

Add `-u` if you want true-coverage estimates (it replaces `Eff_cov` with `True_cov` and estimates the unknown fraction of the sample):

```bash
$SYLPH profile -u donor_catalogue.syldb sketches/*.sylsp -t 32 -o sylph_profiles.tsv
```

---

## The output

| Column | What it is |
|---|---|
| `Sample_file` | Which sample — key back to `samples.tsv` |
| `Genome_file` | Which donor MAG — key back to `catalogue_metadata.tsv` |
| **`Adjusted_ANI`** | Coverage-adjusted containment ANI — the identity measure |
| **`Eff_cov`** / `True_cov` | Estimated coverage of that genome in that sample |
| `Taxonomic_abundance` | Relative abundance (%) — **not used here** |
| `Sequence_abundance` | Percentage of reads assigned — **not used here** |
| `ANI_5-95_percentile` | Confidence interval on the ANI; `NA-NA` when coverage is too low |
| `Containment_ind` | Genome k-mers found / total, e.g. `959/1053` |
| `Naive_ANI` | Unadjusted ANI |
| `Contig_name` | Name of the genome's *first contig* — **not** the MAG name; use `Genome_file` |

Only **`Adjusted_ANI`** and a coverage column feed the analysis. The two abundance columns are ignored throughout — the readout here is how many donor MAGs are detected, not how much of each is present.

**Only genomes passing the threshold appear.** A MAG absent from a sample's rows was not detected — absence is encoded as a missing row, so you must expand the table to a full genome × sample matrix before counting anything. Step 2 below does this, and skipping it is the most common way to get wrong numbers.

---

## Calling engraftment

Two criteria, applied identically to every sample:

```
Detected  ⇔  Adjusted_ANI >= 99.9   AND   Eff_cov >= 0.05
```

**ANI ≥ 99.9%** is the strain-identity criterion. **Coverage ≥ 0.05×** is the detection floor — sylph needs roughly 0.01–0.05× coverage at minimum for a bacterial genome, and an ANI computed from a handful of k-mers is not worth acting on however high it looks. Requiring both stops a high-ANI, near-zero-coverage row from counting as presence.

Then, per donor MAG and per recipient:

| Pre-FMT | Post-FMT | Call |
|:-:|:-:|---|
| ✗ | ✓ | **Engraftment** |
| ✓ | ✓ | **Pre-existing** — present before FMT; donor origin not established |
| ✗ | ✗ | **Not detected** |
| ✓ | ✗ | **Lost** |

The `✓ ✓` row is the one to be careful with. The MAG is in the donor catalogue *and* was already in the recipient before transplant, so post-FMT presence attributes to neither source. Report these separately; do not fold them into the engraftment count.

> **The one case that fools this.** sylph reports ANI to the *best-matching* population in a sample. If the recipient carries their own strain of the same species, it shares most of the donor MAG's genome and can clear 99.9% on its own. The pre-FMT baseline normally catches that — the relative is detected at Day00 and the MAG is classified `pre_existing`. The gap is a recipient strain that sits **below detection pre-FMT and blooms afterwards**: it then reads as absent-then-present, i.e. engraftment. Post-FMT blooms are common, so for your headline engraftment calls, check the Day00 coverage of that MAG. A MAG with coverage just under the threshold pre-FMT is a different proposition from one with no signal at all.

---

## Working through it in R

Copy the profile table, your `samples.tsv` and the catalogue metadata somewhere local, then work through these steps. Each block builds on the last.

### Step 1 — load the three tables

```r
library(dplyr)
library(tidyr)

prof    <- read.delim("sylph_profiles.tsv", check.names = FALSE)
samples <- read.delim("samples.tsv", comment.char = "#")
catalog <- read.delim("donor_MAG_catalogue/catalogue_metadata.tsv")

# sylph reports file paths; reduce them to the ids used in the other tables.
#   .../Donor_01.paired.sylsp -> Donor_01
#   .../Donor_01_MAG001.fa    -> Donor_01_MAG001
prof <- prof %>%
  mutate(
    sample_id = sub("\\.paired$", "", tools::file_path_sans_ext(basename(Sample_file))),
    mag_id    = sub("\\.(fa|fna|fasta)$", "", basename(Genome_file))
  )

# Coverage is Eff_cov normally, True_cov if you ran sylph with -u.
cov_col <- intersect(c("True_cov", "Eff_cov"), names(prof))[1]
cat("Using coverage column:", cov_col, "\n")
```

### Step 2 — expand to a full matrix

This is the step people skip, and it quietly breaks everything downstream. **sylph only emits a row for genomes it detected**, so "not detected" is a *missing row*, not a zero. Count straight off the profile table and every absence vanishes.

```r
MIN_ANI <- 99.9
MIN_COV <- 0.05

detection <- expand_grid(
    mag_id    = catalog$mag_id,
    sample_id = samples$sample_id
  ) %>%
  left_join(
    prof %>% select(mag_id, sample_id, Adjusted_ANI, cov = all_of(cov_col)),
    by = c("mag_id", "sample_id")
  ) %>%
  mutate(
    detected = !is.na(Adjusted_ANI) & !is.na(cov) &
               Adjusted_ANI >= MIN_ANI & cov >= MIN_COV
  )

sum(detection$detected)   # sanity check
```

### Step 3 — check your positive control

Before anything else: each donor's own MAGs must come back from that donor's own sample. They were built from it.

```r
detection %>%
  inner_join(catalog %>% select(mag_id, donor_id), by = "mag_id") %>%
  filter(sample_id == donor_id) %>%
  summarise(.by = donor_id,
            own_mags = n(),
            recovered = sum(detected),
            pct = round(100 * mean(detected), 1))
```

`pct` should be high — near 100%. If a donor recovers few of its own MAGs, stop and fix that before interpreting any recipient result.

### Step 4 — classify each MAG per recipient

Compare each recipient's post-FMT samples against their Day00 baseline, restricted to **their own donor's** MAGs.

```r
recip <- samples %>% filter(sample_type == "recipient")

pre <- recip %>%
  filter(timepoint == "Day00") %>%
  select(subject_id, donor_id, pre_sample = sample_id)

calls <- recip %>%
  filter(timepoint != "Day00") %>%
  select(subject_id, donor_id, timepoint, post_sample = sample_id) %>%
  inner_join(pre, by = c("subject_id", "donor_id")) %>%
  # only this recipient's own donor's MAGs
  inner_join(catalog %>% select(mag_id, donor_id), by = "donor_id",
             relationship = "many-to-many") %>%
  left_join(detection %>% select(mag_id, pre_sample = sample_id, pre_det = detected),
            by = c("mag_id", "pre_sample")) %>%
  left_join(detection %>% select(mag_id, post_sample = sample_id, post_det = detected,
                                 ani_post = Adjusted_ANI, cov_post = cov),
            by = c("mag_id", "post_sample")) %>%
  mutate(call = case_when(
    !pre_det &  post_det ~ "engraftment",
     pre_det &  post_det ~ "pre_existing",
     pre_det & !post_det ~ "lost",
    TRUE                 ~ "not_detected"
  ))

table(calls$call)
```

### Step 5 — summarise

```r
summary_tbl <- calls %>%
  summarise(.by = c(subject_id, donor_id, timepoint),
    engrafted    = sum(call == "engraftment"),
    pre_existing = sum(call == "pre_existing"),
    lost         = sum(call == "lost"),
    evaluated    = n()
  ) %>%
  mutate(proportion = round(engrafted / evaluated, 3)) %>%
  arrange(subject_id, timepoint)

summary_tbl
write.table(summary_tbl, "engraftment_summary.tsv", sep = "\t",
            quote = FALSE, row.names = FALSE)
```

Always carry `evaluated` alongside `proportion`. The denominator is the donor's catalogue size, which tracks their sequencing depth — so a bare percentage is not comparable between donors.

### Step 6 — plot

```r
library(ggplot2)

# Detection heatmap, one panel per recipient
detection %>%
  inner_join(samples, by = "sample_id") %>%
  filter(sample_type == "recipient") %>%
  ggplot(aes(timepoint, mag_id, fill = detected)) +
    geom_tile(colour = "grey90", linewidth = 0.2) +
    facet_wrap(~ subject_id, scales = "free_x") +
    scale_fill_manual(values = c(`TRUE` = "#2c7fb8", `FALSE` = "grey95"), name = NULL) +
    labs(x = NULL, y = "Donor MAG",
         subtitle = sprintf("ANI >= %s, coverage >= %s", MIN_ANI, MIN_COV)) +
    theme_minimal(base_size = 9) +
    theme(axis.text.y = element_text(size = 4), panel.grid = element_blank())

ggsave("heatmap.pdf", width = 9, height = 10, limitsize = FALSE)

# Engraftment over time
ggplot(summary_tbl, aes(timepoint, proportion, group = subject_id)) +
  geom_line(colour = "grey60") +
  geom_point(size = 2.2, colour = "#2c7fb8") +
  facet_wrap(~ subject_id) +
  scale_y_continuous(limits = c(0, 1), labels = scales::percent) +
  labs(x = NULL, y = "Donor MAGs engrafted") +
  theme_minimal(base_size = 10)

ggsave("engraftment_over_time.pdf", width = 8, height = 5)
```

### Step 7 — examine the pre-FMT baseline

The Day00 sample is not just a filter — it is the most informative sample you have for interpreting everything else. Before FMT, how much donor-like material did each recipient already carry?

This is where keeping the catalogue un-dereplicated pays off. A recipient strain sitting at ~99.9% identity to one of the donor's MAGs is reported in its own right, so you can see it.

```r
baseline <- pre %>%
  inner_join(catalog %>% select(mag_id, donor_id), by = "donor_id",
             relationship = "many-to-many") %>%
  left_join(detection %>% select(mag_id, pre_sample = sample_id,
                                 ani_pre = Adjusted_ANI, cov_pre = cov),
            by = c("mag_id", "pre_sample")) %>%
  mutate(baseline_status = case_when(
    is.na(ani_pre)                          ~ "absent",
    ani_pre >= MIN_ANI & cov_pre >= MIN_COV ~ "near-identical, detected",
    ani_pre >= MIN_ANI                      ~ "near-identical, low coverage",
    TRUE                                    ~ "related, below ANI threshold"
  ))

baseline %>% count(subject_id, baseline_status)
```

How to read the four states:

| Baseline status | Meaning |
|---|---|
| `absent` | Nothing resembling this donor genome pre-FMT. Later detection is a clean engraftment call. |
| `near-identical, detected` | The recipient already carried this strain. Post-FMT presence is ambiguous — classified `pre_existing`. |
| `near-identical, low coverage` | A near-identical strain was faintly there. **The ambiguous case** — see below. |
| `related, below ANI threshold` | Same species, different strain. Later detection of the donor strain is genuine, and interesting: it means strain replacement, not colonisation of empty niche. |

Then screen the engraftment calls against it:

```r
calls %>%
  filter(call == "engraftment") %>%
  left_join(baseline %>% select(mag_id, subject_id, baseline_status),
            by = c("mag_id", "subject_id")) %>%
  count(timepoint, baseline_status)
```

Anything landing in `near-identical, low coverage` is your weakest set: a near-identical genome *was* faintly present pre-FMT and only failed the coverage floor, so the post-FMT signal could be the recipient's own strain expanding rather than the donor's establishing. Report those separately rather than dropping them — the distinction is the interesting part, not an inconvenience.

### Step 8 — check threshold sensitivity

`MIN_ANI` and `MIN_COV` are analytical choices. Re-run steps 2–5 across a range and see whether your conclusions move:

```r
sapply(c(99.0, 99.5, 99.9, 99.95), function(a) {
  d <- prof %>% filter(Adjusted_ANI >= a, .data[[cov_col]] >= MIN_COV)
  nrow(d)
})
```

If 99.5% and 99.9% tell different stories, that is worth knowing before you write it up — and worth reporting either way.

---

## Reading the result

A detection matrix for one recipient:

```
                    Day00   Day07   Day28
Donor_01_MAG001       -       +       +
Donor_01_MAG002       -       +       -
Donor_01_MAG003       +       +       +
Donor_01_MAG004       -       -       +
```

- **MAG001** — absent before, present at both post timepoints: engraftment with persistence. The strongest pattern available.
- **MAG002** — appears then disappears: transient detection. Delivered but did not establish, *or* dropped below the detection floor. Check its coverage at Day07 before calling it transient.
- **MAG003** — present throughout: pre-existing, ambiguous origin.
- **MAG004** — appears only at Day28: either delayed establishment or it was below detection earlier. Depth-dependent, so check the sequencing depth of Day00 and Day07.

### Engraftment proportion

```
proportion = engrafted MAGs / donor MAGs evaluated
```

Report the denominator alongside it. "35 of 100 donor MAGs" is interpretable; "35%" alone is not, because the denominator depends on how many MAGs that donor yielded — which depends on their sequencing depth and assembly quality, not their biology. Donors with deeper sequencing produce larger catalogues and will look different for purely technical reasons.

### Before you believe a number

- **Did the donor's own MAGs come back from the donor sample?** The positive control from stage 3. If not, nothing downstream is trustworthy.
- **Are post-FMT samples sequenced as deeply as pre-FMT?** Systematically shallower pre-FMT samples create apparent engraftment, because "absent before" is easier to achieve at low depth.
- **Do engrafted MAGs have reasonable CheckM2 contamination?** A contaminated MAG picks up hits from organisms unrelated to the donor. Cross-check the engraftment hits against `catalogue_metadata.tsv`.
- **Absence is a weak claim at any depth.** Not detected means not detected at this depth with these thresholds — not biologically absent.

---

## Where to go next

The natural extensions, in rough order of effort:

- **Vary the thresholds** and report sensitivity. Cheapest and most informative.
- **Add timepoints.** Persistence at a late timepoint is far stronger evidence than detection at day 7.
- **Sequence the weak calls deeper.** The `high ANI, low coverage` group from step 7 is where extra depth changes the answer, rather than where extra tooling does.
- **Relate engraftment to outcome** — the clinical question this is usually a means to.

See [the concepts guide](concepts/engraftment.md) for the definitions and their limits.
