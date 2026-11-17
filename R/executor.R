#' Run a rendered script
#'
#' STUB. A small interface with interchangeable backends, selected by
#' `cfg$executor$type`:
#' - "local": background R process via callr (the only one planned for the
#'   prototype)
#' - "slurm": submit the same script with sbatch and poll (later)
#'
#' Each backend provides submit, status and cancel.
#'
#' @param script Path to the script to run.
#' @param cfg Configuration list from [load_config()].
#' @return A job handle.
#' @noRd
executor_submit <- function(script, cfg) {
  rlang::abort("executor_submit() is not implemented yet.")
}

#' @noRd
executor_status <- function(job) {
  rlang::abort("executor_status() is not implemented yet.")
}

#' @noRd
executor_cancel <- function(job) {
  rlang::abort("executor_cancel() is not implemented yet.")
}
