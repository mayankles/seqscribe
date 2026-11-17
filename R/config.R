#' Load seqscribe configuration
#'
#' Layers, lowest to highest priority:
#' 1. the packaged `config.yml` (profile chosen by `R_CONFIG_ACTIVE`)
#' 2. `config.local.yml` in the working directory, if present
#' 3. the `SEQSCRIBE_LLM_API_KEY` environment variable, for the API key
#'
#' @param config_file Optional path to use instead of the packaged file.
#' @return A named list.
#' @noRd
load_config <- function(config_file = NULL) {
  if (is.null(config_file)) {
    config_file <- system.file("config", "config.yml", package = "seqscribe")
    if (!nzchar(config_file)) config_file <- file.path("inst", "config", "config.yml")
  }
  cfg <- config::get(file = config_file)

  local_file <- "config.local.yml"
  if (file.exists(local_file)) {
    cfg <- utils::modifyList(cfg, yaml::read_yaml(local_file))
  }

  key <- Sys.getenv("SEQSCRIBE_LLM_API_KEY", unset = "")
  if (nzchar(key)) cfg$llm$api_key <- key

  cfg
}
