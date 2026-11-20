# Decision log

Newest first. Each entry: the decision, then the reason.

## 2026-11-19: plot options from older helper functions

Options taken from Mayank's older helpers (`makePCAplot_MT`, `makeVolcano`),
rewritten to the library contract; the helpers themselves are not imported.

- **`plot_pca` 0.3.0 computes the PCA itself** with `prcomp()` on the same
  top-variable genes DESeq2's `plotPCA` uses, because `plotPCA` returns only
  PC1 and PC2. New options: any two components, sample labels, 95% ellipses
  per colour group (skipped, with a note, for groups under 3 samples),
  loading arrows for the top genes, and scaling. **Scaling is off by
  default** to match DESeq2; the old helper scaled by default. The summary
  now includes the top loading genes for both components. The `ntop` limit
  was raised to 100000 (0.2.1) so a large value means all genes.
- **`plot_volcano` 0.2.0 labels the most significant genes:** `label_top`
  per direction, with `label_direction` choosing up, down or both (default:
  top 5 up and top 5 down).
  It uses a `symbol` column when the results have one, else gene IDs, so a
  later gene-annotation entry makes labels readable without changing it.
- Not taken: plotly output, automatic fold-change column detection, and the
  helpers' own file saving (the runner saves results).
- Deferred, with prerequisites: gene annotation (symbols, Entrez IDs);
  Reactome enrichment with top-level categories (needs annotation, several
  contrasts per project and an offline Reactome file); Venn or UpSet overlap
  of DE gene sets (needs several contrasts).

## 2026-11-19: first chat runs

The five demo requests from the chat greeting, sent through the chat three
times with `openai/gpt-oss-20b` in LM Studio (16k context, temperature 0,
no streaming). Each request took 11 to 21 seconds.

- **Fixed: every chat message crashed the app.** shinychat 0.5.0 can send the
  input as a list of content objects instead of a string; the handler now
  accepts both and passes them to ellmer with `!!!`. File attachments are
  turned off in the chat, because the LLM must never see raw data.
- **Function and argument choice was right in all three runs:** `dex` as the
  condition, `untrt` as the reference, `cell` as the covariate, PCA coloured
  by cell, `trt` versus `untrt`. Numbers it quoted came from the summaries.
- **It ran a step it was not asked for,** in all three runs: after the sample
  table request it also ran `build_dds`. The system prompt forbids this; a
  prompt rule alone does not hold.
- **It interprets beyond the numbers,** for example calling the cell-line
  separation on PC2 "a strong batch effect". Whether interpretation in chat
  is allowed, and how it is labelled, is not decided yet.
- **After loading data it asked which column to compare** instead of
  proposing `dex` from the metadata summary.
- Not yet tested: Gemma 4 12B, error recovery through the chat, ambiguous or
  out-of-library requests.

## 2026-11-16 (first run): what running the prototype showed

Run on R 4.6.1 with ellmer 0.5.2, shinychat 0.5.0, shiny 1.14.0, DESeq2
1.52.0. The tests pass, the demo runs through `run_step()`, the generated
`run_all.R` runs on its own, the report renders, and the app runs the demo
from the manual form with no LLM server. The chat was tested on 2026-11-19
(next entry).

Fixed:

- **The session died on load.** The report-steps observer called `setNames()`
  on `NULL` when no steps existed.
- **Result cards were squashed to their headers** by the fill layout; the
  results feed is now wrapped in a plain div.
- **`shiny::runApp()` sourced `R/` itself** as well as `app.R` loading the
  package. `R/_disable_autoload.R` turns that off (the golem convention).
- **shinychat 0.5.0 deprecated `chat_ui(messages =)`;** now `greeting =`.
- **Functions are offered in workflow order,** not alphabetically, in the
  manual form and to the LLM.

Decided after the first run:

- **Replacing an object removes everything derived from it.** The runner
  records what each object was made from (the producing entry's `inputs`).
  When a step replaces an object, objects derived from the old one are
  dropped, and the user and the model are told which. Reason: rebuilding the
  sample table used to leave the old `dds` and `de_results` in place, so
  later plots silently used the old design; only the system prompt asked for
  a rebuild. An object updated from itself (`dds` in `run_deseq2`) keeps its
  ancestry. Later steps then fail with "Missing input: ... (run X first)".
- **A design that cannot be fitted is an error, not a warning**
  (`set_sample_table` 0.2.0). A covariate with one value, or a design that is
  not full rank, fails the step and leaves the sample table unchanged. Groups
  without replicates remain a warning.

Found and left open (each needs a decision, not just a fix):

- **Methods text is filled from the arguments, not the result.** With no
  `reference_level` given, the report says "reference level: none" while R
  used the first level alphabetically. Methods text should be able to use
  values from the step's `summary`.
- **The generated script saves nothing.** It recomputes objects and plots but
  writes no files, so results cannot be regenerated without the app.
- **Rendering the report needs pandoc on the PATH.** On the Mac it exists only
  inside RStudio; launched outside RStudio the app writes the Rmd and stops.
  Set `RSTUDIO_PANDOC` or install pandoc.
- **Every browser session creates a project folder,** even if nothing runs.

## 2026-11-16 (later): prototype implementation choices

- **Project state is a plain environment per session,** with a counter the UI
  watches. Reason: tools run inside async chat calls, where a simple
  non-reactive store is the least fragile.
- **Non-streaming chat by default** (`llm.stream: false`). Reason: tool
  calling with streaming is unreliable on some local servers. Try `true` once
  the basics work.
- **Steps run in the app's own R process.** Simple, but blocks the UI during
  DESeq2. The executor interface is still a stub; background execution comes
  with the first slow function.
- **A manual "run a function" form** is generated from the library entries.
  Reason: it separates R problems from LLM problems and shows the
  "controls from the library" idea working.
- **Errors go back to the model as tool results** with the allowed values, so
  it can correct itself; only successful steps are recorded in the script.
- **Re-running a function appends a new step** and does not replace the old
  one. Revisit when the script should be editable.
- **`set_sample_table` stands in for the sample parser:** the model picks the
  condition column, reference and covariates from a column summary. The
  free-text and GEO parser is still to be built.
- **Library function contract:** arguments are inputs then params; return a
  list with any of `objects`, `plot`, `table`, `summary`.

## 2026-11-16 (later): demo datasets

- **Prototype demo: airway (GSE52778).** Small, and its package includes the
  GEO series matrix, so the sample parser can be tested on real GEO metadata.
- **Batch examples: pasilla (GSE18508)** for a technical covariate handled in
  the design, and **the GFRN series (GSE83083, GSE59765)** for true batch
  correction. Batch correction is out of scope for the first prototype slice;
  blocking on cell line in airway covers the simple case.
  See `inst/extdata/README.md`.

## 2026-11-16 (later): library-first

- **The library is the product; the LLM is the interface.** Having the model
  look up and call tested functions is faster and more reliable than having
  it write code, and gives a place for guardrails.
- **Self-contained library entries** (`inst/library/<name>/` with `entry.yml`,
  `function.R`, optional `report.Rmd`), replacing the earlier split between
  the package's `R/` folder and `inst/registry/`. Reason: the library must be
  editable and updatable without rebuilding the package.
- **Layered libraries:** built-in, then user folders that extend or override.
- **Versioned entries;** projects record version and hash and keep a copy of
  the functions they used, so library updates never change old analyses.
- **Guided and open modes.** Guided restricts the assistant to library
  functions; open also allows custom code.
- **Custom code is always recorded** as a custom block, even when written by
  hand, to keep projects reproducible.
- **Promotion path** from custom block to library entry, to be built early.
  Reason: a library-first tool is only as good as its library, and it should
  grow from real use.
- **Scaling plan for tool selection:** send everything, then filter by step,
  then search summaries and tags. True retrieval is deferred until the
  library is large.

## 2026-11-16

- **Name: seqscribe** (no hyphen, so the repo and R package share it).
  "seqsmith" was the runner-up.
- **MIT license, private GitHub repo for now.**
- **Prototype before full library.** A thin end-to-end slice comes first, to
  get a feel for the GUI and to test local-model tool calling early. The
  original plan (library first, then renderer, then UI, then LLM) is
  reordered accordingly.
- **Chat-driven workbench, not a strict wizard.** The goal is to direct
  routine analyses in plain language; the steps are a guide, not a gate.
- **Highly configurable through files.** Settings, registry, workflows,
  prompts and report templates are all editable without touching app code.
- **Assume the LLM is on the same node as the app.** Mirrors the Mac setup and
  defers cluster networking questions. Reversible by config.
- **LM Studio for development**, serving an OpenAI-compatible endpoint.
  Default model `openai/gpt-oss-20b`; Gemma 4 12B QAT as comparison. Ollama
  was considered and offers nothing extra here.
- **The app talks to an address, not a provider.** It never launches the LLM
  server itself.
- **Spec plus registry architecture.** The LLM fills in a validated spec and
  calls registered functions; it does not write the analysis freehand by
  default. This is what makes a small local model usable and provides the
  guardrails needed for less expert users later.
- **R package layout, Shiny + bslib, ellmer, shinychat, callr.**
- **Bulk RNA-seq first; scRNA-seq and arbitrary analyses later.**

## Open

- Cluster hosting details (see `hpc-questions.md`).
- Input scope: counts matrix only, or also Salmon/featureCounts output?
- Whether existing personal R functions seed the library or it starts fresh.
