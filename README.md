![Logo](https://cbg-ethz.github.io/V-pipe/img/logo.svg)

V-pipe is a workflow designed for the analysis of next generation sequencing (NGS) data from viral pathogens. It produces a number of results in a curated format (consensus sequences, SNV calls, local/global haplotypes).


[![bio.tools](https://img.shields.io/badge/bio-tools-blue.svg)](https://bio.tools/V-Pipe)
[![Snakemake](https://img.shields.io/badge/snakemake-≥6.5.1-blue.svg)](https://snakemake.github.io/snakemake-workflow-catalog/?usage=cbg-ethz/V-pipe)
[![Deploy Docker image](https://github.com/cbg-ethz/V-pipe/actions/workflows/deploy-docker.yaml/badge.svg)](https://github.com/cbg-ethz/V-pipe/pkgs/container/v-pipe)
[![Tests](https://github.com/kpj/rwrap/actions/workflows/main.yml/badge.svg)](https://github.com/kpj/rwrap/actions/workflows/main.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)


## Usage

We use a [two-level](https://github.com/cbg-ethz/V-pipe/wiki/getting-started#input-files) directory hierarchy and we expect sequencing reads in a folder name `raw_data`.
Further details can be found on the [wiki](https://github.com/cbg-ethz/V-pipe/wiki) pages and [website](https://cbg-ethz.github.io/V-pipe/usage/).

To setup V-pipe, you have the following options.

### Using quick install script

To deploy V-pipe, you can use the installation script with the following parameters:

```bash
curl -O 'https://raw.githubusercontent.com/cbg-ethz/V-pipe/master/utils/quick_install.sh'
./quick_install.sh -w work
```

This script will download and install miniconda, checkout the V-pipe repository (use `-b` to specify which branch/tag) and setup a work directory (use `-w`) with an executable script:

```bash
cd work
# edit config.yaml and provide samples directory
./vpipe -j 4 -n
```

### Using Docker

Note: the docker image is only setup with components to run the workflow for HIV and SARS-CoV-2 virus base configurations.
Using V-pipe with other viruses or configurations might require internet connectivity for additional software components.

Populate the `samples` directory and create `config.yaml` or `vpipe.config`.
For example, the following config file could be used:
```yaml
general:
  virus_base_config: hiv

output:
  snv: true
  local: true
  global: false
  visualization: true
  QA: true
```

Then execute:

```bash
docker run --rm -it -v $PWD:/work ghcr.io/cbg-ethz/v-pipe:master -j 4 -n
```

### Using snakedeploy

You first need to install [mamba](https://github.com/conda-forge/miniforge#mambaforge). You can then create and activate an environment with Snakemake and Snakedeploy:

```bash
mamba create -c bioconda -c conda-forge --name snakemake snakemake snakedeploy
conda activate snakemake
```

Snakemake's official workflow installer Snakedeploy can then be used:

```bash
snakedeploy deploy-workflow https://github.com/cbg-ethz/V-pipe --tag master .
# edit config/config.yaml and provide samples directory
snakemake -j 4 -n
```


## Dependencies

- **conda**

  Conda is a cross-platform package management system and an environment manager application.

- **Snakemake**

  Snakemake is the central workflow and dependency manager of V-pipe. It determines the order in which individual tools are invoked and checks that programs do not exit unexpectedly.

- **VICUNA**

  VICUNA is a *de novo* assembly software designed for populations with high mutation rates. It is used to build an initial reference for mapping reads with ngshmmalign aligner when a `references/cohort_consensus.fasta` file is not provided. Further details can be found in the [wiki](https://github.com/cbg-ethz/V-pipe/wiki/getting-started#input-files) pages.

### Computational tools
Other dependencies are managed by using isolated conda environments per rule, and below we list some of the computational tools integrated in V-pipe:

- **PRINSEQ**

  Trimming and clipping of reads is performed by PRINSEQ. It is currently the most versatile raw read processor with many customization options.

- **Vicuna**

  Vicuna is a de novo assembler designed for generating rough reference contigs of viral NGS data. It can deal with the inherent heterogeneity such as high single-base heterogeneity and structural variants.

- **ngshmmalign**

  We perform the alignment of the curated NGS data using our custom ngshmmalign that takes structural variants into account. It produces multiple consensus sequences that include either majority bases or ambiguous bases.

- **bwa**

  In order to detect specific cross-contaminations with other probes, the Burrows-Wheeler aligner is used. It quickly yields estimates for foreign genomic material in an experiment.

- **MAFFT**

  To standardise multiple samples to the same reference genome (say HXB2 for HIV-1), the multiple sequence aligner MAFFT is employed. The multiple sequence alignment helps in determining regions of low conservation and thus makes standardisation of alignments more robust.

- **Samtools**

  The Swiss Army knife of alignment postprocessing and diagnostics.

- **SmallGenomeUtilities**

  We perform genomic liftovers to standardised reference genomes using our in-house developed python library of utilities for rewriting alignments.

- **ShoRAH**

  ShoRAh performs SNV calling and local haplotype reconstruction by using bayesian clustering.

- **HaploClique and SAVAGE**

  We use HaploClique or SAVAGE to perform global haplotype reconstruction for heterogeneous viral populations by using an overlap graph.


## Citation

If you use this software in your research, please cite:

Posada-Céspedes S., Seifert D., Topolsky I., Jablonski K.P., Metzner K.J., and Beerenwinkel N. 2021.
"V-pipe: a computational pipeline for assessing viral genetic diversity from high-throughput sequencing data."
_Bioinformatics_, January. doi:[10.1093/bioinformatics/btab015](https://doi.org/10.1093/bioinformatics/btab015).


## Contributions

- [Ivan Topolsky* ![orcid]](https://orcid.org/0000-0002-7561-0810), [![github]](https://github.com/dryak)
- [Kim Philipp Jablonski ![orcid]](https://orcid.org/0000-0002-4166-4343), [![github]](https://github.com/kpj)
- [Lara Fuhrmann ![orcid]](https://orcid.org/0000-0001-6405-0654), [![github]](https://github.com/LaraFuhrmann)
- [Uwe Schmitt ![orcid]](https://orcid.org/0000-0002-4658-0616), [![github]](https://github.com/uweschmitt)
- [Monica Dragan ![orcid]](https://orcid.org/X), [![github]](https://github.com/monicadragan)
- [Susana Posada Céspedes](https://orcid.org/0000-0002-7459-8186)
- [David Seifert](https://orcid.org/0000-0003-4739-5110)
- Tobias Marschall
- [Niko Beerenwinkel** ![orcid]](https://orcid.org/0000-0002-0573-6119)

\* software maintainer
\** group leader

[github]: https://cbg-ethz.github.io/V-pipe/img/mark-github.svg
[orcid]: https://cbg-ethz.github.io/V-pipe/img/ORCIDiD_iconvector.svg

## Contact

We encourage users to use the [issue tracker](https://github.com/cbg-ethz/V-pipe/issues). For further enquiries, you can also contact the V-pipe Dev Team <v-pipe@bsse.ethz.ch>.
