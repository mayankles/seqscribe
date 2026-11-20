#' Custom code cells
#'
#' A cell runs the user's own R code against the project, for inspecting
#' objects and quick plots. Each successful run is recorded as a custom step
#' in the script and spec, so the project stays reproducible. Shiny-free.
#'
#' Rules:
#' - Project objects (`dds`, `de_results`, ...) are visible by name but cannot
#'   be changed: a cell that assigns one fails and is not recorded. Only
#'   library steps change project objects, so the recorded script and the
#'   app's state stay in step.
#' - Variables a cell creates persist for later cells (`state$scratch`).
#' - Output is never sent to the LLM.
#' @name custom
#' @noRd
NULL

#' Run one code cell
#' @return list(ok, error, output, step). `output` is the console text, also
#'   returned on failure so the user can see what went wrong.
#' @noRd
run_custom <- function(state, code, max_chars = 20000) {
  code <- paste(code, collapse = "\n")
  if (!nzchar(trimws(code))) return(list(ok = FALSE, error = "Nothing to run.", output = ""))
  if (identical(state$cfg$mode, "guided")) {
    return(list(ok = FALSE, error = "Custom code is turned off in guided mode.", output = ""))
  }

  # Project objects are rebuilt in a fresh parent each run; the user's own
  # variables live in a persistent child.
  objects_env <- list2env(state$objects, parent = globalenv())
  if (is.null(state$scratch)) state$scratch <- new.env(parent = objects_env)
  parent.env(state$scratch) <- objects_env
  before <- ls(state$scratch, all.names = TRUE)

  res <- evaluate::evaluate(code, envir = state$scratch, stop_on_error = 1L)

  text <- character()
  plots <- list()
  error <- NULL
  for (r in res) {
    if (inherits(r, "source")) {
      next
    } else if (is.character(r)) {
      text <- c(text, r)
    } else if (inherits(r, "recordedplot")) {
      plots <- c(plots, list(r))
    } else if (inherits(r, "error")) {
      error <- conditionMessage(r)
      text <- c(text, paste0("Error: ", error, "\n"))
    } else if (inherits(r, "warning")) {
      text <- c(text, paste0("Warning: ", conditionMessage(r), "\n"))
    } else if (inherits(r, "message")) {
      text <- c(text, conditionMessage(r))
    }
  }

  clobbered <- intersect(ls(state$scratch, all.names = TRUE), names(state$objects))
  if (length(clobbered) > 0) {
    rm(list = clobbered, envir = state$scratch)
    error <- paste0(
      "Cells can't change project objects (", paste(clobbered, collapse = ", "),
      "); only library steps can. Assign the result to a new name instead."
    )
  }

  output <- paste(text, collapse = "")
  if (nchar(output) > max_chars) {
    output <- paste0(substr(output, 1, max_chars),
                     "\n... output truncated at ", max_chars, " characters.\n")
  }
  if (!is.null(error)) {
    # Undo variables created by the failed cell, so a rerun starts clean.
    new_vars <- setdiff(ls(state$scratch, all.names = TRUE), before)
    if (length(new_vars) > 0) rm(list = new_vars, envir = state$scratch)
    return(list(ok = FALSE, error = error, output = output))
  }

  step_id <- sprintf("%02d_custom", length(state$steps) + 1L)
  step_dir <- file.path(state$project_dir, "results", step_id)
  dir.create(step_dir, recursive = TRUE, showWarnings = FALSE)
  plot_rel <- character()
  for (i in seq_along(plots)) {
    rel <- file.path("results", step_id, sprintf("plot_%d.png", i))
    grDevices::png(file.path(state$project_dir, rel), width = 7, height = 5, units = "in", res = 110)
    grDevices::replayPlot(plots[[i]])
    grDevices::dev.off()
    plot_rel <- c(plot_rel, rel)
  }
  if (nzchar(output)) writeLines(output, file.path(step_dir, "output.txt"))

  step <- list(
    id = step_id,
    type = "custom",
    fn = "custom",
    title = "Custom code",
    workflow_step = NA_character_,
    layer = "custom",
    params = list(),
    summary = NULL,
    plot = if (length(plot_rel) > 0) plot_rel,
    output = if (nzchar(output)) output,
    code = strsplit(code, "\n", fixed = TRUE)[[1]],
    methods = "Custom code, not from the function library.",
    time = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
  state$steps[[step_id]] <- step
  save_project_files(state)
  list(ok = TRUE, error = NULL, output = output, step = step)
}
