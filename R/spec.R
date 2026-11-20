#' Analysis spec: the project's record of what was done
#'
#' Written to `spec.yml` in the project folder after every step, so a killed
#' session leaves a complete record. Reading a spec back to resume a project
#' is not implemented yet.
#' @name spec
#' @noRd
NULL

#' @noRd
spec_build <- function(state) {
  st <- state$objects$sample_table
  samples <- if (!is.null(st)) {
    lapply(seq_len(nrow(st)), function(i) lapply(as.list(st[i, , drop = FALSE]), as.character))
  }
  list(
    seqscribe_version = tryCatch(
      as.character(suppressWarnings(utils::packageDescription("seqscribe", fields = "Version"))),
      error = function(e) NA_character_
    ),
    workflow = state$workflow,
    mode = state$cfg$mode,
    llm = list(model = state$cfg$llm$model, base_url = state$cfg$llm$base_url),
    samples = samples,
    # Library calls and custom code cells, in the order they ran.
    steps = lapply(unname(state$steps), function(s) {
      if (is_custom(s)) {
        list(id = s$id, type = "custom", code = paste(s$code, collapse = "\n"),
             status = "done", time = s$time)
      } else {
        list(
          id = s$id, type = "library", fn = s$fn, fn_version = s$version, fn_hash = s$hash,
          layer = s$layer, params = s$params, status = "done", time = s$time
        )
      }
    })
  )
}

#' @noRd
spec_write <- function(state) {
  yaml::write_yaml(spec_build(state), file.path(state$project_dir, "spec.yml"))
}

#' STUB: resume a project from its spec.
#' @noRd
spec_read <- function(project_dir) {
  rlang::abort("spec_read() is not implemented yet.")
}
