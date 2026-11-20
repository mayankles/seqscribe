# seqscribe: project context

This file brings an AI coding assistant (or a new human contributor) up to
speed. Read it before changing anything. Deeper detail is in `docs/`.

## Vision

seqscribe is a curated, editable library of analysis functions with a
plain-language interface. Instead of writing the code as they go, the analyst
directs a routine analysis in plain language, and a locally hosted LLM
translates each request into calls to the library.

**The library is the product; the LLM is the interface to it.** Having the
model look up and call tested functions, instead of writing code, is faster
(a function name and arguments, not a script), more reliable (it chooses among
validated options) and gives a natural place for guardrails.

- **First workflow:** bulk RNA-seq (counts matrix in, differential expression
  report out).
- **Later:** scRNA-seq, then arbitrary analyses.
- **Users now:** bioinformaticians and data scientists. The tool is a coding
  assistant: everything it does is visible and editable as code.
- **Users later, maybe:** bench scientists, once the guardrails are strong
  enough. Design choices should not close that door.
- **Feel:** a chat-driven workbench with a guided path. The steps (metadata,
  QC, methods, report) are a map showing where you are, not a gate; the user
  can jump around.

## Design principles

These are the load-bearing decisions. Do not work around them without
recording the change in `docs/decisions.md`.

1. **The LLM edits a spec; it does not write the analysis freehand.**
   Each project has one analysis spec (YAML) holding the sample table, design,
   chosen methods, parameters and selected report blocks. The LLM proposes
   changes to the spec and calls registered functions. Scripts and reports are
   rendered from the spec deterministically. Free-form LLM code exists only as
   a clearly marked "custom block" that is shown before it runs.
2. **One function library drives everything.** Every analysis function is a
   self-contained library entry: the R code plus a definition (summary, tags,
   inputs, outputs, parameters with allowed values, methods text, report
   fragment). The same entries generate the UI controls, the LLM tool schema,
   the script and the report. Adding a capability means adding a library
   entry, not editing app code. See "The function library" below.
3. **The LLM never sees raw data.** It sees metadata and computed summaries.
   All numbers come from R.
4. **Every action is visible as code.** Each step appends to a running script
   the user can read, edit and rerun.
5. **Projects are reproducible without the app or the LLM.** The output is a
   project folder (spec, scripts, results, Rmd) that runs on its own.
6. **Highly configurable through plain files.** App settings, library,
   workflows, prompts and report templates all live under `inst/` as editable
   files. Build the seam for each, but ship only one of each until needed.
7. **Deterministic first, LLM for the residue.** Where a parser or a fuzzy
   match can do the job (for example reading a GEO series matrix), use it, and
   give the LLM only what is left.
8. **Validate everything the LLM returns** against the library and the spec
   schema before acting on it.

## The function library

- **Self-contained entries.** One folder per function under `inst/library/`:
  `entry.yml`, `function.R`, optional `report.Rmd`. Editing or adding an entry
  needs no package rebuild. `plot_pca` is the reference example.
- **Layers.** The built-in library ships with the package. User library
  folders (config: `library.user_dirs`) extend it and override entries of the
  same name. A shared team library can later be a git repo used as one of
  those folders.
- **Versioned.** Each entry has a version. A project's spec records the
  version and content hash of every function it used, so updating the library
  never silently changes an old analysis.
- **Checked on load.** A malformed entry is reported and skipped; it must not
  break the app.
- **Two modes** (config: `mode`).
  - `guided`: the assistant can use library functions only. This is the mode
    intended for less expert users.
  - `open`: the user can also add their own code as custom blocks.
- **Custom code is always recorded.** Code the user adds by hand gets no
  guardrails, but it is still stored in the script and spec as a custom
  block, so the project stays reproducible.
- **Promotion path.** A custom block that proves useful can be saved to the
  user library as a proper entry; the LLM drafts the summary, tags and
  parameter descriptions and the user confirms. This is how the library is
  meant to grow: from real use, not from guessing in advance. Build this
  early, because a library-first tool will often have to say "I don't have a
  function for that".
- **Scaling how functions reach the LLM.**
  1. Small library: every definition is sent on each turn.
  2. Growing library: filter by workflow and current step first.
  3. Large library: add a search over each entry's `summary` and `tags`
     (retrieval). Write good summaries and tags from the start.
  Local models have small context windows, so step 2 matters early.

## The three components

1. **Sample parser.** Builds a simplified sample table from free text or
   tabular input (for example a GEO metadata table) and matches sample names
   to the columns of the input data. Validation: every data column matched
   exactly once, enough replicates per group, design matrix full rank (catches
   batch confounded with condition). The user confirms in an editable table
   with the source text beside each proposed value.
2. **Script builder.** Renders the spec into a script that calls library
   functions. Escape hatch: a custom block of LLM-written code, reviewed
   before running, executed in a separate R process.
3. **Report builder.** Each completed step emits a result block (code, figure
   or table, methods text). The user picks blocks; they are stitched into a
   parameterised Rmd. LLM-written interpretation is optional, labelled, and
   limited to numbers passed to it.

## Three seams that must stay configurable

| Seam | Development (Mac) | Later (Slurm cluster) |
|---|---|---|
| LLM address | LM Studio on `localhost` | a server on the same node (assumed), or `node:port` |
| Executor | background R process | the same, then `sbatch` for heavy jobs |
| Paths | local project folder | cluster filesystem, picked by path, not uploaded |

The app reads an LLM base URL, model name and optional API key from config.
It never starts or owns the LLM server, and never hard-codes a provider.

## Current state (2026-11-19)

- First prototype written (2026-11-16) and **run end to end**, from the
  manual form and from the chat with `openai/gpt-oss-20b` in LM Studio
  (2026-11-19): tests pass, the generated script runs on its own and the
  report renders. The model completed the five demo requests correctly in
  three of three runs, but also ran a step it was not asked for. What the
  first runs found, fixed and left open is in `docs/decisions.md` ("first
  run" and "first chat runs"). Screenshots are in `README.md`.
- What the prototype implements:
  - Library loader with checks and layers (`R/library.R`), and eight built-in
    entries: `load_demo_airway`, `set_sample_table`, `build_dds`,
    `plot_library_sizes`, `plot_pca`, `plot_sample_correlation`,
    `run_deseq2`, `plot_volcano`.
  - The step runner (`R/runner.R`): every call, from the LLM or the manual
    form, is validated, run, saved to the project folder and recorded.
  - Tools generated from library entries, plus `get_project_state`.
  - Script builder (`R/script.R`), spec writer (`R/spec.R`), report builder
    (`R/report.R`), three-panel UI.
  - A code cell above the results (`R/custom.R`, `R/code_cell.R`): the
    user's own R code against the project, recorded as custom steps. Hidden
    and refused when `mode` is `guided`. Project objects are read-only from
    a cell. Up/Down recall earlier commands (browser-side history).
- Not implemented yet: LLM-written custom blocks, the promotion path, resuming a project
  from its spec, the free-text and GEO sample parser (`set_sample_table` is a
  column-picking stand-in), editable sample table, background execution
  (steps run in the app's own R process and block it), version-mismatch
  handling, tool selection beyond "send everything".
- Library function contract: arguments are the entry's `inputs` (objects from
  project state, by name) followed by its `params`. Return a list with any of
  `objects` (named list stored into project state), `plot` (ggplot), `table`
  (data frame) and `summary` (small list; the only part the LLM sees).
- Development machine: Apple Silicon Mac, 24 GB memory, LM Studio.
- Models on hand: `openai/gpt-oss-20b` (MLX, default) and Gemma 4 12B QAT
  (GGUF, comparison and low-memory fallback). Context length should be raised
  to about 16k for tool calling.
- Deployment target: a work Slurm cluster that can launch arbitrary Shiny apps
  through a GUI. Cluster details are unknown and deferred; see
  `docs/hpc-questions.md`. Working assumption: the LLM is served on the same
  node as the app, as on the Mac.
- Stack: R package layout, Shiny + bslib, ellmer for the LLM, shinychat for
  the chat panel, callr for background execution.

## Handoff: first tasks

The prototype was written in a session with no R and no access to the local
LLM. **All seven tasks are done** (1 to 5 on 2026-11-16, 6 and 7 on
2026-11-19), though task 7 covers only `gpt-oss-20b` on the scripted five
requests; Gemma and error recovery in the chat are untested. Kept here as a
record and as a checklist for setting up a new machine.

1. `git init` and make the first commit if the repo has no history yet.
2. Install the packages listed in `README.md`.
3. Run the tests: `pkgload::load_all(); testthat::test_dir("tests/testthat")`.
   These need no LLM and exercise the config, the library loader and call
   validation.
4. Run the library functions directly, without the app or the LLM, in the
   demo order: `load_demo_airway`, `set_sample_table` (condition `dex`,
   reference `untrt`, covariate `cell`), `build_dds`, the three QC plots,
   `run_deseq2` (`trt` versus `untrt`), `plot_volcano`. Use
   `new_state()` and `run_step()` so the runner is tested too.
5. Launch the app with no LLM server running. Confirm the warning banner
   appears and the manual form can run the whole demo.
6. Start the LM Studio server and test the chat. Likely trouble spots:
   - `llm_client()`: argument names of `ellmer::chat_openai_compatible()`
   - `library_as_tools()`: `ellmer::tool()` and the `type_*()` calls
   - `app_server()`: whether the results panel refreshes after the assistant
     runs a step (the `bump()` call after `shinychat::chat_append()`)
7. Record how the local model handles the five requests in the chat greeting:
   right function, right arguments, recovery from errors. This is the
   question the prototype exists to answer.

## The prototype

A thin end-to-end slice whose purpose is to get a feel for the GUI and to test
whether a local model can reliably pick the right function and arguments.
It now runs end to end, from the manual form and from the chat. The next
step is to decide, from hands-on use, what to change before growing the
library.

- **Layout:** step navigator on the left, results in the centre, chat on the
  right, a tab for the running script.
- **One slice:** load counts and metadata, build the sample table, QC with a
  PCA, one DESeq2 contrast, a short Rmd report.
- **Eight library functions**, not the full library.
- **Demo dataset:** airway (GSE52778) from its Bioconductor package. Batch
  examples for later are listed in `inst/extdata/README.md`.

## Roadmap after the prototype

0. ~~A code cell in the app~~ (done 2026-11-19, first version of `open`
   mode). Possible follow-ups: using a project from the R console (the core
   in `R/runner.R` and `R/custom.R` is already Shiny-free), running cells in
   a background process so a long cell does not block the app.
1. Flesh out the bulk RNA-seq function library and standardise it; build the
   promotion path (custom block to library entry).
2. Build an evaluation set: 15 to 20 GEO series with hand-curated sample
   tables, to compare models and prompts objectively.
3. Methods advisor (design, batch handling, method choice).
4. Slurm executor and cluster packaging, after talking to HPC staff.
5. scRNA-seq workflow as new library entries and workflow files.

## Conventions

- R package layout; app code in `R/`, everything configurable in `inst/`.
- Shiny modules for each panel; no business logic in UI code.
- To add an analysis function: create `inst/library/<name>/` with
  `entry.yml` and `function.R`, plus `report.Rmd` if it produces output worth
  reporting. See `inst/library/README.md`.
- Library functions return a list whose `summary` element is the only part
  the LLM sees.
- Relative URLs only (the app may be served under a sub-path by an HPC portal).
- Write the spec to disk on every change; "resume project" must always work,
  because a cluster job can be killed at walltime.
- Every "fetch from the internet" feature needs a "use a file I already have"
  path; compute nodes may have no internet.

## Known constraints

- ellmer with local servers: tool calling and streaming may not combine, and
  structured-output calls disable tool calling. Keep parsing calls and
  tool-using chat calls separate. Re-check against the installed ellmer
  version before relying on either.
- MLX model files only run on Apple Silicon; the cluster will need the same
  model in another format.
- Prompts tuned on one model may not transfer. Record the model in the spec.

## Do not

- Hard-code an LLM provider, address or model.
- Send raw counts or other bulk data to the LLM.
- Run LLM-written code without showing it to the user first.
- Let the LLM state a number that R did not compute.
- Put analysis functions in the package's `R/` folder; they belong in the
  library so users can edit them.
- Change a library function's behaviour without bumping its version.
