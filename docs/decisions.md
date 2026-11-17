# Decision log

Newest first. Each entry: the decision, then the reason.

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
