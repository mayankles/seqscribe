# Architecture

Status: design, not yet implemented. Dated 2026-11-16.

## Overview

```
 user (chat + UI)
        |
        v
  +-----------+   tool calls / proposed edits   +----------------+
  |  LLM      | <-----------------------------> |  seqscribe app |
  | (local)   |   metadata + summaries only     |                |
  +-----------+                                 |  library       |
                                                |  spec (YAML)   |
                                                |  executor      |
                                                +-------+--------+
                                                        |
                                 rendered script        v
                                                +----------------+
                                                | R process      |
                                                | (callr; later  |
                                                |  sbatch)       |
                                                +-------+--------+
                                                        |
                                                        v
                                              project folder on disk
```

## Project folder

One folder per analysis. Everything needed to reproduce the analysis without
the app lives here.

```
<project>/
  spec.yml          the analysis spec (single source of truth)
  inputs/           links or copies of counts and metadata
  scripts/          rendered scripts, one per step, plus run_all.R
    library/        copies of the library functions this project used
  results/          tables, figures, RDS objects, one subfolder per step
  report/           report.Rmd and its rendered output
  log/              chat transcript and tool-call log
```

## Analysis spec

Draft shape. To be formalised as a schema and validated on every write.

```yaml
seqscribe_version: 0.0.0.9000
workflow: bulk_rnaseq
llm: {model: openai/gpt-oss-20b, base_url: "http://localhost:1234/v1"}
inputs:
  counts: inputs/counts.tsv
  metadata_source: inputs/GSE0000_series_matrix.txt
samples:                      # the curated sample table
  - {sample_id: S1, data_column: GSM000001, condition: control, batch: A, include: true}
design:
  formula: "~ batch + condition"
  contrasts:
    - {name: treated_vs_control, factor: condition, numerator: treated, denominator: control}
steps:                        # ordered calls to library functions
  - {id: qc_pca, fn: plot_pca, fn_version: 0.1.0, fn_hash: "a1b2c3", layer: builtin,
     params: {color_by: condition, ntop: 500}, status: done}
  - {id: de_main, fn: run_deseq2, fn_version: 0.1.0, fn_hash: "d4e5f6", layer: builtin,
     params: {alpha: 0.05}, status: pending}
mode: open                    # guided or open, as set when the project ran
custom_blocks: []             # user- or LLM-written code, always recorded
report:
  blocks: [qc_pca, de_main]
```

## Function library

The library is the core of the system. One self-contained folder per function:

```
<name>/
  entry.yml     summary, tags, version, parameters, outputs, methods text
  function.R    defines one function called <name>
  report.Rmd    optional report fragment
```

`inst/library/plot_pca/` is the reference example.

**How entries are used**

1. **UI:** parameter controls are generated from `params`.
2. **LLM:** each entry becomes a tool definition (name, summary, typed
   arguments, allowed values).
3. **Script builder:** the call is generated from the function name and the
   parameters in the spec; the script sources the function from a copy kept
   with the project.
4. **Report builder:** `methods_text` and `report.Rmd` produce the block.

**Layers and loading**

- Built-in library (`inst/library/`), then each folder in
  `library.user_dirs`; later layers override earlier ones by name.
- Each entry is checked on load (required fields, parameter types, function
  name and arguments match the definition). Problems are reported in the app
  and the entry is skipped.
- Functions are sourced into a dedicated environment, not the global one.

**Versioning and reproducibility**

- Each entry carries a version; the loader also computes a content hash.
- The spec records version, hash and layer for every step.
- When a step first runs, the function's file is copied into the project's
  `scripts/library/` folder, so the project runs without the app and is
  unaffected by later library edits.
- If a project's recorded hash differs from the current library, the app says
  so and offers to keep the project's copy or re-run with the new version.

**Modes**

- `guided`: only library functions can be called.
- `open`: custom blocks are also allowed. Custom code is always recorded in
  the spec and script, whether the user or the LLM wrote it.

**Promotion path**

A custom block can be saved to the user library: the code is wrapped as a
function, the LLM drafts `entry.yml` (summary, tags, parameter descriptions),
the user edits and confirms, and the entry is written to the first user
library folder and loaded.

**Getting the right functions to the LLM**

| Library size | Approach |
|---|---|
| Small (tens) | Send every tool definition each turn |
| Growing | Filter by workflow and current step |
| Large (hundreds) | Also search `summary` and `tags`, send the top matches |

The threshold is `library.max_tools_in_context`. Search can start as keyword
matching and move to embeddings if needed.

## Sample parser pipeline

1. Detect the input type (GEO series matrix, SOFT, delimited table, free text).
2. Deterministic parse: split `key: value` characteristics, tidy column names.
3. Deterministic match of sample IDs to data columns (exact, then fuzzy).
4. LLM pass on what is left: classify fields (phenotype, batch, ignore),
   harmonise levels, resolve ambiguous matches. Structured output only.
5. Validate: one-to-one matching, replicates per group, full-rank design.
6. User confirms in an editable table; the result is written to the spec.

## Chat loop

1. User message arrives.
2. The app sends it with: the system prompt, the current step, a compact view
   of the spec, and the tool definitions selected from the library.
3. The LLM replies with text, tool calls, or both.
4. Each tool call is validated against the library, shown to the user as
   code, executed by the executor, and recorded in the spec.
5. A short summary of the result (never raw data) goes back to the LLM.

## Executor

A small interface with two implementations:

- `local`: run the script in a background R process (callr), report status.
- `slurm` (later): submit the same script with `sbatch`, poll status.

## Configuration layers

Lowest to highest priority:

1. `inst/config/config.yml` shipped with the package (profiles: default,
   local, hpc; chosen by `R_CONFIG_ACTIVE`).
2. `config.local.yml` in the working directory (not committed).
3. Environment variables for secrets (`SEQSCRIBE_LLM_API_KEY`).

## HPC deployment (deferred)

Working assumption: the LLM server runs on the same node as the Shiny app, so
the address is `localhost` as on the Mac. If HPC staff recommend a separate
GPU job instead, the server writes a connection file (host, port, key) to the
user's home directory and the app reads it; nothing else changes. On a shared
cluster the server must require an API key.
