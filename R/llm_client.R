#' Create a chat client for the configured LLM
#'
#' The app talks to an address, never to a specific provider: any server with
#' an OpenAI-compatible API works (LM Studio, llama.cpp, Ollama, vLLM).
#'
#' @param cfg Configuration list from [load_config()].
#' @param system_prompt Character string.
#' @return An ellmer chat object.
#' @noRd
llm_client <- function(cfg, system_prompt) {
  key <- cfg$llm$api_key
  if (is.null(key) || !nzchar(key)) key <- "not-needed"
  chat <- ellmer::chat_openai_compatible(
    base_url = cfg$llm$base_url,
    model = cfg$llm$model,
    credentials = function() key,
    params = ellmer::params(temperature = cfg$llm$temperature %||% 0),
    echo = "none"
  )
  chat$set_system_prompt(system_prompt)
  chat
}

#' Check that the configured LLM server is reachable and has the model
#' @return list(ok, model_found, models, message)
#' @noRd
llm_health_check <- function(cfg) {
  url <- paste0(sub("/+$", "", cfg$llm$base_url), "/models")
  res <- tryCatch({
    req <- httr2::req_timeout(httr2::request(url), 3)
    key <- cfg$llm$api_key
    if (!is.null(key) && nzchar(key)) req <- httr2::req_auth_bearer_token(req, key)
    body <- httr2::resp_body_json(httr2::req_perform(req))
    vapply(body$data, function(m) m$id %||% "", "")
  }, error = function(e) e)

  if (inherits(res, "error")) {
    return(list(ok = FALSE, model_found = FALSE, models = character(),
                message = paste0("No LLM server answered at ", cfg$llm$base_url,
                                 ". Start the local server, then reload.")))
  }
  found <- cfg$llm$model %in% res
  list(
    ok = TRUE, model_found = found, models = res,
    message = if (found) {
      paste0("Connected to ", cfg$llm$model, " at ", cfg$llm$base_url, ".")
    } else {
      paste0("Server found at ", cfg$llm$base_url, ", but it does not list the model '",
             cfg$llm$model, "'. Available: ", paste(res, collapse = ", "), ".")
    }
  )
}

#' Read and fill the system prompt
#' @noRd
system_prompt <- function(cfg, workflow) {
  dir <- cfg$paths$prompts_dir
  file <- if (!is.null(dir) && nzchar(dir)) file.path(dir, "system.md") else pkg_file("prompts", "system.md")
  text <- paste(readLines(file, warn = FALSE), collapse = "\n")
  gsub("{{workflow_title}}", workflow$title %||% "data", text, fixed = TRUE)
}
