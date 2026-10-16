# Step 0 — Setting up on Setonix

Everything in this tutorial runs on **Setonix**, Pawsey's SLURM cluster. This stage gets your account, storage and software in order. Do it once.

If you have run OpusTaxa on Setonix before, you can skim this — it follows the same conventions as the [OpusTaxa Pawsey guide](https://github.com/yenkaiC/OpusTaxa/blob/main/docs/pawsey.md).

---

## Storage: the one thing to get right

Setonix has three storage areas with very different purposes. Putting things in the wrong one is the most common way to get stuck.

| Location | Variable | Use for | Never use for |
|---|---|---|---|
| Home | `$HOME` | SSH keys, small dotfiles | Anything large — the quota is tiny |
| Software | `$MYSOFTWARE` | Miniconda, Singularity image cache | Sequencing data, pipeline output |
| Scratch | `$MYSCRATCH` | Repos, FASTQ, databases, all output | Long-term storage — **purged after 21 days of inactivity** |

Two rules:

1. **Install conda into `$MYSOFTWARE`.** Installing into `$HOME` blows the quota immediately.
2. **Keep all data and all pipeline working directories on `$MYSCRATCH`.**

> **Scratch is not backup.** Files untouched for 21 days are deleted. Move anything you need to keep — final MAGs, profiles, tables — to Pawsey's long-term storage (Acacia) before you walk away from a project.

### Set up a project directory

```bash
ssh yourusername@setonix.pawsey.org.au
```

```bash
mkdir -p $MYSCRATCH/FMT_engrafter && cd $MYSCRATCH/FMT_engrafter
```

Everything below assumes this is your working root.

---

## Your project code

Every SLURM job must be charged to an allocation. Your project code looks like `pawseyXXXX`.

```bash
echo $MYSCRATCH
```

The path is `/scratch/pawseyXXXX/yourusername` — the `pawseyXXXX` part is your project code. To list every project you can charge to:

```bash
sacctmgr show assoc user=$(whoami) format=account%20
```

Write it down. You will need it in the OpusTaxa SLURM profile (step 1) and in the Nextflow config (step 2). A wrong or missing account means jobs are rejected at submission, or silently billed to someone else's allocation.

Export it now, and add the line to your `~/.bashrc`:

```bash
export PAWSEY_PROJECT=pawseyXXXX
```

> **Getting the account wrong is the most common way a run dies on its first job.** This walkthrough sets it explicitly in the Nextflow config (`clusterOptions = '--account=pawseyXXXX'`) rather than relying on the variable. Exporting it as well is still useful, because the official `pawsey_setonix` nf-core profile reads `$PAWSEY_PROJECT` if you ever switch to it.

---

## Modules

Setonix provides software as modules. The two you need:

```bash
module load singularity/4.1.0-slurm
module load nextflow/25.04.6
```

Load Singularity for steps 1, 3 and 4; load both for step 2.

If either version has moved on, list what is available:

```bash
module avail 2>&1 | grep -i singularity
module avail 2>&1 | grep -i nextflow
```

> Use the `-slurm` Singularity build. It is the one aware of the scheduler, and container jobs behave badly without it.

---

## Conda (for the Snakemake launcher only)

OpusTaxa is orchestrated by Snakemake, which needs a small conda environment. The *tools* themselves all run from containers — conda here is just the launcher.

```bash
cd $MYSOFTWARE
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p $MYSOFTWARE/miniconda3
source $MYSOFTWARE/miniconda3/etc/profile.d/conda.sh
conda init
```

Log out and back in (or `source ~/.bashrc`) so `conda` is on your path. Then:

```bash
conda create -n snakemake -c conda-forge -c bioconda snakemake
conda activate snakemake
pip install snakemake-executor-plugin-slurm
```

> **Why containers rather than conda for the tools:** Setonix uses a Lustre parallel filesystem. A conda environment creates tens of thousands of small files, which overwhelms Lustre's metadata server, burns through your inode quota, and produces environments that corrupt in ways that are miserable to debug. One `.sif` file per tool avoids all of it.

---

## Singularity image cache

Container images are large, and you do not want them re-downloaded per job or landing in `$HOME`.

Good news: **loading the Nextflow module sets this up for you.** `module load nextflow/25.04.6` exports `NXF_HOME=$MYSOFTWARE/.nextflow` and `NXF_SINGULARITY_CACHEDIR=$MYSOFTWARE/.nextflow_singularity`, precisely because the `$HOME` defaults would blow the quota. You do not need to set those yourself.

For stages 1, 3 and 4 (Snakemake and direct container runs), Snakemake manages its own image directory inside the working directory, which is on `$MYSCRATCH` — also fine.

```bash
module load nextflow/25.04.6
echo $NXF_SINGULARITY_CACHEDIR    # confirm it points into $MYSOFTWARE
```

> Pawsey documents `NXF_SINGULARITY_CACHEDIR` only. If you see advice to export `SINGULARITY_CACHEDIR` on Setonix, treat it as unverified — check what your Nextflow module already sets before overriding anything.

---

## Where to run the orchestrator

Both Snakemake and Nextflow are **orchestrators**: they run continuously for the whole analysis, submitting and monitoring SLURM jobs on your behalf. If your SSH connection drops, the orchestrator dies and the run stops.

Setonix provides **dedicated workflow nodes** for exactly this. Connect to them rather than to a general login node:

```bash
ssh yourusername@setonix-workflow.pawsey.org.au
```

This lands you on `setonix-07` or `setonix-08`. Note which one — to get back to a running session later you must SSH to that specific node:

```bash
ssh yourusername@setonix-08.pawsey.org.au
```

Then start a persistent session and run the orchestrator **directly inside it**:

```bash
screen -S fmt            # create ONCE
conda activate snakemake
# detach: Ctrl+A then D
```

```bash
screen -r fmt            # reattach later
```

> **Create once, then reattach.** Running `screen -S fmt` a second time makes a *new empty* session rather than returning you to the running pipeline. `screen -ls` lists what you already have.

> **Do not `sbatch` or `salloc` the orchestrator.** Pawsey's workflow-node guidance is explicit about this: run the master task directly in your screen/tmux session. The workflow nodes exist to host long-running masters and are not bound by the `long` partition's 96-hour wall time.

> **A note on conflicting Pawsey docs:** Pawsey's older Nextflow page recommends submitting the Nextflow master as a Slurm batch script, while the newer workflow-nodes page says to run it interactively on `setonix-workflow` and not to use `sbatch`. This tutorial follows the newer workflow-nodes guidance. Check both pages if you hit trouble, as the recommendation has changed over time.

---

## Checklist

Before moving to step 1:

- [ ] Working directory created on `$MYSCRATCH`
- [ ] Project code identified and `PAWSEY_PROJECT` exported in `~/.bashrc`
- [ ] `singularity/4.1.0-slurm` and `nextflow/25.04.6` both load
- [ ] `snakemake` conda env created, with the SLURM executor plugin
- [ ] `NXF_SINGULARITY_CACHEDIR` points into `$MYSOFTWARE` after loading the Nextflow module
- [ ] Connected via `setonix-workflow`, with a `screen` session you know how to reattach to (note the node number)

Next: **[Step 1 — Assemble](01-assemble.md)**
