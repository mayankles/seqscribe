# Small helpers shared across the package.

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Path to a file shipped in inst/, working both when installed and when run
#' from the repo root.
#' @noRd
pkg_file <- function(...) {
  path <- system.file(..., package = "seqscribe")
  if (!nzchar(path)) path <- file.path("inst", ...)
  path
}

#' Compact JSON for anything sent to the LLM.
#' @noRd
to_json <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = 4, null = "null", force = TRUE))
}

#' Deparse a parameter value onto one line for the generated script.
#' @noRd
deparse_value <- function(x) {
  paste(deparse(x, width.cutoff = 500L), collapse = "")
}
