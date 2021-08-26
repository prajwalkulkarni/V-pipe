__author__ = "Susana Posada-Cespedes"
__author__ = "David Seifert"
__license__ = "Apache2.0"
__maintainer__ = "Ivan Topolsky"
__email__ = "v-pipe@bsse.ethz.ch"

import csv
import os
import typing

# for legacy
import configparser
import json  # NOTE jsonschema  is only part of the full snakemake, not snakemake-minimal

from collections import UserDict

from snakemake.io import load_configfile
from snakemake.utils import update_config, validate

import logging

LOGGER = logging.getLogger("snakemake.logging")

if not "VPIPE_BENCH" in dir():
    VPIPE_BENCH = False

# even if the --configfile option overload is used this default *must* always exist:
# - the _content_ of these extra configfiles will overwrite the basefile's _content_
# - not the _filenames_ themselves
if os.path.exists("config/config.yaml"):

    configfile: "config/config.yaml"


elif os.path.exists("config.yaml"):

    configfile: "config.yaml"


def load_legacy_ini(ininame, schemaname):
    """
    Load a legacy INI-style config file with Python configparser
    and uses a schema to load it correctly:

    - configparser does not guess the datatpye of value in config files
      always storing them internally as strings.
      it provides getter methods for integers, floats and booleans.

      we apply the getter corresponding to the type expected in the schema

    - configpasrer keys are not case-sensitive and stored in lowercase,
      whereas JSON and YAML are case sensitive.

      we convert to the case expected by the schema
    """
    cp = configparser.ConfigParser()
    cp.read(ininame)

    with open(schemaname) as sf:
        sch = json.load(sf)

    ini = {}
    # build the result structure by:
    # - looping the whole configparser object
    # - applying types from the jsonschema
    # - fixing the case of keys
    for (name, section) in cp.items():
        if name == "DEFAULT":
            # configparser-specific, skip
            continue
        if name not in sch["properties"]:
            # technically, missing part should be handled by validator,
            # but we need valid names anyway to do the types
            raise ValueError(
                "Invalid section in {inif} :".format(sec=name, inif=ininame), name
            )
        ini[name] = {}
        # configpasrer keys are not case-sensitive and stored in lowercase
        lcentries = {k.lower(): k for k in sch["properties"][name]["properties"].keys()}
        for (entry, value) in section.items():
            if entry not in lcentries:
                raise ValueError(
                    "Invalid entry in section {sec} of {inif} :".format(
                        sec=name, inif=ininame
                    ),
                    entry,
                )
            entry = lcentries[entry]
            # configparser doesn't convert type automatically
            # convert if necessary based on schema
            ty = sch["properties"][name]["properties"][entry]["type"]
            if ty == "boolean":
                value = section.getboolean(entry)
            elif ty == "integer":
                value = section.getint(entry)
            elif ty == "number":
                value = section.getfloat(entry)
            # string are left as-is
            ini[name][entry] = value
    return ini


def process_config(config):
    """
    process configuration.

    - precedence logic:
      snakemake (configfile(s) + --confg) >> legacy configparse INI >> virus base config >> schema default

    - validate with schema
    """

    schema = srcdir("../schemas/config_schema.json")

    # merging of legacy INI-style
    if os.path.exists("vpipe.config"):
        LOGGER.info("Importing legacy configuration file vpipe.config")
        # snakemake configuration overwrites legacy vpipe.config
        cur_config = config
        config = load_legacy_ini("vpipe.config", schema)
        update_config(config, cur_config)

    # merging of virus' base configuration
    vf = None
    try:
        # search for file location
        if config["general"]["virus_base_config"]:
            # shorthand - e.g.: hiv
            vf = "{VPIPE_BASEDIR}/../config/{VIRUS}.yaml".format(
                VPIPE_BASEDIR=VPIPE_BASEDIR,
                VIRUS=config["general"]["virus_base_config"],
            )
            if not os.path.exists(vf):
                # normal search (with normal macro expansion, like the default values)
                vf = config["general"]["virus_base_config"].format(
                    VPIPE_BASEDIR=VPIPE_BASEDIR
                )
                if not os.path.exists(vf):
                    raise ValueError(
                        "Cannot find virus base config",
                        config["general"]["virus_base_config"],
                    )
    # (empty entry)
    except TypeError:
        vf = None
    except KeyError:
        vf = None

    if vf:
        # current configuration overwrites virus base config
        cur_config = config
        config = load_configfile(vf)
        if "name" in config:
            LOGGER.info("Using base configuration virus %s" % config.pop("name"))
        else:
            LOGGER.info(
                "Using base configuration from %s"
                % porevious_config["general"]["virus_base_config"]
            )
        update_config(config, cur_config)
    else:
        LOGGER.info("No virus base configuration, using defaults")

    # validates, but also fills up default values:
    validate(config, schema, set_default=True)
    # use general.threads entry as default for all affected sections
    # if not specified:
    for (name, section) in config.items():
        if name == "general":
            continue
        if not isinstance(section, dict):
            continue
        if "threads" not in section:
            section["threads"] = config["general"]["threads"]

        # interpolate some parameters
        # (currently only the base directory for resources packaged in V-pipe)
        for entry, value in section.items():
            if isinstance(value, str):
                section[entry] = value.format(VPIPE_BASEDIR=VPIPE_BASEDIR)

    """
    The following hack supports `.` access to dictionary entries, e.g.
    config.input instead of config["input"] so we don't have to change all
    existing rules.
    This works only on the upper-level of config and not for the nested
    dictionaries.
    """
    config = UserDict(config)
    config.__dict__.update(config)
    return config


config = process_config(config)

# 2. glob patients/samples + store as TSV if file is not provided

# if file containing samples exists, proceed
# to build list of target files
if not os.path.isfile(config.input["samples_file"]):
    # sample file does not exist, have to first glob
    # all patients' data and then construct sample
    # list that would pass QA checks

    patient_sample_pairs = glob_wildcards(
        "{}/{{patient_date}}/raw_data/{{file}}".format(config.input["datadir"])
    )

    if not set(patient_sample_pairs.patient_date):
        LOGGER.warning(
            f"WARNING: No samples found in {config.input['datadir']}. Not generating {config.input['samples_file']}."
        )
    else:
        with open(config.input["samples_file"], "w") as outfile:
            for i in set(patient_sample_pairs.patient_date):
                (patient, date) = [x.strip() for x in i.split("/") if x.strip()]
                outfile.write("{}\t{}\n".format(patient, date))

# TODO: have to preprocess patient files to filter likely failures
# 1.) Determine 5%/95% length of FASTQ files
# 2.) Determine whether FASTQ would survive


# 3. load patients from TSV and create list of samples
#
# This list is reused on subsequent runs

patient_list = []
patient_dict = {}
patient_record = typing.NamedTuple(
    "patient_record", [("patient_id", str), ("date", str)]
)

if not os.path.isfile(config.input["samples_file"]):
    LOGGER.warning(
        f"WARNING: Sample list file {config.input['samples_file']} not found."
    )
else:
    with open(config.input["samples_file"], newline="") as csvfile:
        spamreader = csv.reader(csvfile, delimiter="\t")

        for row in spamreader:
            if len(row) == 0 or row[0][0] == "#":
                # Skip completely empty lines, or comments begining with '#' (numpy style)
                continue
            assert (
                len(row) >= 2
            ), "ERROR: Line '{}' does not contain at least two entries!".format(
                spamreader.line_num
            )
            patient_tuple = patient_record(patient_id=row[0], date=row[1])
            patient_list.append(patient_tuple)

            assert (
                config.input["trim_percent_cutoff"] > 0
                and config.input["trim_percent_cutoff"] < 1
            ), "ERROR: 'trim_percent_cutoff' is expected to be a fraction (between 0 and 1), whereas 'trim_percent_cutoff'={}".format(
                config.input["trim_percent_cutoff"]
            )
            assert (
                patient_tuple not in patient_dict
            ), "ERROR: sample '{}-{}' is not unique".format(row[0], row[1])

            if len(row) == 2:
                # All samples are assumed to have same read length and the default, 250 bp
                patient_dict[patient_tuple] = config.input["read_length"]

            elif len(row) >= 3:
                # Extract read length from input.samples_file. Samples may have
                # different read lengths. Reads will be filtered out if read length
                # after trimming is less than trim_cutoff * read_length.
                patient_dict[patient_tuple] = int(row[2])

# 4. generate list of target files
all_files = []
alignments = []
vicuna_refs = []
references = []
consensus = []
trimmed_files = []
fastqc_files = []
results = []
visualizations = []
datasets = []
IDs = []
for p in patient_list:

    alignments.append(
        "{sample_dir}/{patient}/{date}/alignments/REF_aln.bam".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )
    # if config.output["QA"]:
    #    alignments.append(
    #        "{sample_dir}/{patient}/{date}/QA_alignments/coverage_ambig.tsv".format(
    #            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
    #        )
    #    )
    #    alignments.append(
    #        "{sample_dir}/{patient}/{date}/QA_alignments/coverage_majority.tsv".format(
    #            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
    #        )
    #    )

    vicuna_refs.append(
        "{sample_dir}/{patient}/{date}/references/vicuna_consensus.fasta".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )
    references.append(
        "{sample_dir}/{patient}/{date}/references/ref_".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )

    consensus.append(
        "{sample_dir}/{patient}/{date}/references/ref_ambig.fasta".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )
    consensus.append(
        "{sample_dir}/{patient}/{date}/references/ref_majority.fasta".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )

    consensus.append(
        "{sample_dir}/{patient}/{date}/references/consensus.bcftools.fasta".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )

    if config.output["QA"]:
        alignments.append(
            "{sample_dir}/{patient}/{date}/references/ref_majority_dels.matcher".format(
                sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
            )
        )
        alignments.append(
            "{sample_dir}/{patient}/{date}/references/frameshift_deletions_check.tsv".format(
                sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
            )
        )

    trimmed_files.append(
        "{sample_dir}/{patient}/{date}/preprocessed_data/R1.fastq.gz".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )
    if config.input["paired"]:
        trimmed_files.append(
            "{sample_dir}/{patient}/{date}/preprocessed_data/R2.fastq.gz".format(
                sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
            )
        )

    fastqc_files.append(
        "{sample_dir}/{patient}/{date}/extracted_data/R1_fastqc.html".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )
    if config.input["paired"]:
        fastqc_files.append(
            "{sample_dir}/{patient}/{date}/extracted_data/R2_fastqc.html".format(
                sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
            )
        )

    datasets.append(
        "{sample_dir}/{patient}/{date}".format(
            sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
        )
    )
    IDs.append(("{}-{}").format(p.patient_id, p.date))

    # SNV
    if config.output["snv"]:
        # in adition to standard VCF files, ShoRAH2 also produces CSV tables
        if config.general["snv_caller"] == "shorah":
            results.append(
                "{sample_dir}/{patient}/{date}/variants/SNVs/snvs.csv".format(
                    sample_dir=config.input["datadir"],
                    patient=p.patient_id,
                    date=p.date,
                )
            )
        # all snv callers ('shorah', 'lofreq') produce standard VCF files
        results.append(
            "{sample_dir}/{patient}/{date}/variants/SNVs/snvs.vcf".format(
                sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
            )
        )
    # local haplotypes
    if config.output["local"]:
        results.append(
            "{sample_dir}/{patient}/{date}/variants/SNVs/snvs.csv".format(
                sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
            )
        )
    # global haplotypes
    if config.output["global"]:
        if config.general["haplotype_reconstruction"] == "savage":
            results.append(
                "{sample_dir}/{patient}/{date}/variants/global/contigs_stage_c.fasta".format(
                    sample_dir=config.input["datadir"],
                    patient=p.patient_id,
                    date=p.date,
                )
            )
        elif config.general["haplotype_reconstruction"] == "haploclique":
            results.append(
                "{sample_dir}/{patient}/{date}/variants/global/quasispecies.bam".format(
                    sample_dir=config.input["datadir"],
                    patient=p.patient_id,
                    date=p.date,
                )
            )
        elif config.general["haplotype_reconstruction"] == "predicthaplo":
            if config.input["paired"]:
                results.append(
                    "{sample_dir}/{patient}/{date}/variants/global/predicthaplo_haplotypes.fasta".format(
                        sample_dir=config.input["datadir"],
                        patient=p.patient_id,
                        date=p.date,
                    )
                )
            else:
                raise NotImplementedError(
                    "PredictHaplo only works with paired-end reads"
                )

    # visualization
    if not config.output["snv"] and config.output["visualization"]:
        raise RuntimeError(
            "Cannot generate visualization without calling variants (make sure to set `snv = True`) in config."
        )

    if config.output["snv"] and config.output["visualization"]:
        visualizations.append(
            "{sample_dir}/{patient}/{date}/visualization/index.html".format(
                sample_dir=config.input["datadir"], patient=p.patient_id, date=p.date
            )
        )

    # merge lists containing expected output
    all_files = alignments + consensus + results + visualizations

IDs = ",".join(IDs)

# 5. Locate reference and parse reference identifier
def get_reference_name(reference_file):
    with open(reference_file, "r") as infile:
        reference_name = infile.readline().rstrip()
    reference_name = reference_name.split(">")[1]
    reference_name = reference_name.split(" ")[0]
    return reference_name


if not VPIPE_BENCH:
    reference_file = config["input"]["reference"]
    if not os.path.isfile(reference_file):
        reference_file_alt = os.path.join("references", reference_file)
        LOGGER.warning(
            f"WARNING: Reference file {reference_file} not found. Trying {reference_file_alt}."
        )
        reference_file = reference_file_alt
        if not os.path.isfile(reference_file):
            raise ValueError(f"ERROR: Reference file {reference_file} not found.")

    reference_name = get_reference_name(reference_file)


# Auxiliary functions


def ID(wildcards):
    return "-".join(os.path.normpath(wildcards.dataset).split(os.path.sep)[-2:])


def window_lengths(wildcards):
    window_len = []
    for p in patient_list:
        read_len = patient_dict[p]
        aux = int((read_len * 4 / 5 + config.snv["shift"]) / config.snv["shift"])
        window_len.append(str(aux * config.snv["shift"]))

    window_len = ",".join(window_len)
    return window_len


def shifts(wildcards):
    shifts = []
    for p in patient_list:
        read_len = patient_dict[p]
        aux = int((read_len * 4 / 5 + config.snv["shift"]) / config.snv["shift"])
        shifts.append(str(aux))

    shifts = ",".join(shifts)
    return shifts


def get_maxins(wildcards):
    if config.bowtie_align["maxins"]:
        return config.bowtie_align["maxins"]
    else:
        parts = wildcards.dataset.split("/")
        patient_ID = parts[1]
        date = parts[2]
        read_len = patient_dict[patient_record(patient_id=patient_ID, date=date)]
        return 4 * read_len


def construct_input_fastq(wildcards):
    indir = os.path.join(wildcards.dataset, "raw_data")
    aux = glob_wildcards(
        indir + "/{prefix, [^/]+}" + "{ext, (\.fastq|\.fastq\.gz|\.fq|\.fq\.gz)}"
    )
    if config.input["paired"]:
        inferred_values = glob_wildcards(
            indir
            + "/{file}R"
            + wildcards.pair
            + config.input["fastq_suffix"]
            + aux.ext[0]
        )
    else:
        inferred_values = glob_wildcards(indir + "/{file}" + aux.ext[0])

    list_output = []
    file_extension = aux.ext[0].split(".gz")[0]
    for i in inferred_values.file:
        if config.input["paired"]:
            list_output.append(
                os.path.join(
                    indir,
                    "".join(
                        (
                            i,
                            "R",
                            wildcards.pair,
                            config.input["fastq_suffix"],
                            file_extension,
                        )
                    ),
                )
            )
        else:
            list_output.append(os.path.join(indir, "".join((i, file_extension))))
    if len(list_output) == 0:
        raise ValueError(
            "Missing input files for rule extract: {}/raw_data/ - Unexpected file name?".format(
                wildcards.dataset
            )
        )

    return list_output