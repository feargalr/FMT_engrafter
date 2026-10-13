# Stage 0 — Setting up on Setonix

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

Write it down. You will set it in two places: the OpusTaxa SLURM profile (stage 1) and the Nextflow config (stage 2). A wrong or missing account means jobs are rejected at submission, or silently billed to someone else's allocation.

---

## Modules

Setonix provides software as modules. The two you need:

```bash
module load singularity/4.1.0-slurm
module load nextflow/25.04.6
```

Load Singularity for stages 1, 3 and 4; load both for stage 2.

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

Container images are large and you do not want them re-downloaded per job, or landing in `$HOME`. Point the cache at `$MYSOFTWARE`:

```bash
export SINGULARITY_CACHEDIR=$MYSOFTWARE/.singularity
export NXF_SINGULARITY_CACHEDIR=$MYSOFTWARE/.singularity
mkdir -p $SINGULARITY_CACHEDIR
```

Add both lines to your `~/.bashrc` so they apply to every session. `NXF_SINGULARITY_CACHEDIR` is the one Nextflow reads in stage 2; `SINGULARITY_CACHEDIR` covers stages 1, 3 and 4.

---

## Persistent sessions

Both Snakemake and Nextflow are **orchestrators**: they run continuously, submitting and monitoring SLURM jobs on your behalf. If your SSH connection drops, the orchestrator dies and the run stops.

So run them inside `screen` (or `tmux`), on the login node:

```bash
screen -S fmt            # create ONCE
conda activate snakemake
# detach: Ctrl+A then D
```

```bash
screen -r fmt            # reattach later
```

> **Create once, then reattach.** Running `screen -S fmt` a second time makes a *new empty* session rather than returning you to the running pipeline. `screen -ls` lists what you already have.

> **Never `sbatch` the orchestrator itself.** Snakemake and Nextflow need to stay on the login node to talk to the SLURM controller. Submitting them as jobs breaks job submission from inside.

---

## Checklist

Before moving to stage 1:

- [ ] Working directory created on `$MYSCRATCH`
- [ ] Project code `pawseyXXXX` identified
- [ ] `singularity/4.1.0-slurm` and `nextflow/25.04.6` both load
- [ ] `snakemake` conda env created, with the SLURM executor plugin
- [ ] `SINGULARITY_CACHEDIR` and `NXF_SINGULARITY_CACHEDIR` exported in `~/.bashrc`
- [ ] A `screen` session you know how to reattach to

Next: **[Stage 1 — OpusTaxa](01-opustaxa.md)**
