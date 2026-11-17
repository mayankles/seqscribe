#' Function library: load, check, select, expose to the LLM
#'
#' The library is the core of seqscribe; the LLM is an interface to it.
#' Each entry is a self-contained folder (entry.yml, function.R, optional
#' report.Rmd). See inst/library/README.md.
#' @name library
#' @noRd
NULL

#' Load the function library
#'
#' Reads entries from the built-in library, then from each folder in
#' `cfg$library$user_dirs` (later folders override earlier ones by name).
#' A malformed entry is reported and skipped, never fatal.
#'
#' @return list(entries = named list, problems = character vector)
#' @noRd
load_library <- function(cfg) {
  user_dirs <- as.character(unlist(cfg$library$user_dirs))
  dirs <- c(pkg_file("library"), user_dirs)
  layers <- c("builtin", rep("user", length(user_dirs)))
  fn_env <- new.env(parent = globalenv())
  entries <- list()
  problems <- character()

  for (i in seq_along(dirs)) {
    d <- path.expand(dirs[[i]])
    if (!dir.exists(d)) {
      problems <- c(problems, paste("Library folder not found:", d))
      next
    }
    for (entry_dir in list.dirs(d, recursive = FALSE)) {
      res <- read_entry(entry_dir, fn_env)
      if (length(res$problems) > 0) {
        problems <- c(problems, paste0(basename(entry_dir), ": ", res$problems))
        next
      }
      res$entry$layer <- layers[[i]]
      entries[[res$entry$name]] <- res$entry
    }
  }
  list(entries = entries, problems = problems)
}

#' Read and check one library entry
#' @return list(entry = list or NULL, problems = character vector)
#' @noRd
read_entry <- function(entry_dir, fn_env) {
  yml <- file.path(entry_dir, "entry.yml")
  rfile <- file.path(entry_dir, "function.R")
  if (!file.exists(yml)) return(list(entry = NULL, problems = "missing entry.yml"))
  if (!file.exists(rfile)) return(list(entry = NULL, problems = "missing function.R"))

  entry <- tryCatch(yaml::read_yaml(yml), error = function(e) conditionMessage(e))
  if (is.character(entry)) {
    return(list(entry = NULL, problems = paste("entry.yml does not parse:", entry)))
  }

  problems <- character()
  for (field in c("name", "version", "title", "summary", "step")) {
    if (is.null(entry[[field]])) problems <- c(problems, paste("missing field:", field))
  }
  if (length(problems) > 0) return(list(entry = NULL, problems = problems))
  if (!identical(entry$name, basename(entry_dir))) {
    problems <- c(problems, "name in entry.yml does not match the folder name")
  }

  entry$inputs <- as.character(unlist(entry$inputs))
  entry$produces <- as.character(unlist(entry$produces))
  entry$requires <- as.character(unlist(entry$requires))
  entry$params <- entry$params %||% list()
  param_names <- vapply(entry$params, function(p) p$name %||% "", "")
  names(entry$params) <- param_names
  known_types <- c("string", "integer", "number", "boolean", "string_list")
  for (p in entry$params) {
    if (!isTRUE(p$type %in% known_types)) {
      problems <- c(problems, paste0("parameter '", p$name, "' has unknown type"))
    }
  }

  tmp <- new.env(parent = globalenv())
  sourced <- tryCatch({
    sys.source(rfile, envir = tmp)
    TRUE
  }, error = function(e) conditionMessage(e))
  if (!isTRUE(sourced)) {
    problems <- c(problems, paste("function.R does not load:", sourced))
  } else if (!is.function(tmp[[entry$name]])) {
    problems <- c(problems, paste0("function.R does not define a function called '", entry$name, "'"))
  } else {
    missing_args <- setdiff(c(entry$inputs, param_names), names(formals(tmp[[entry$name]])))
    if (length(missing_args) > 0) {
      problems <- c(problems, paste("function is missing arguments:", paste(missing_args, collapse = ", ")))
    }
  }
  if (length(problems) > 0) return(list(entry = NULL, problems = problems))

  assign(entry$name, tmp[[entry$name]], envir = fn_env)
  entry$fun <- tmp[[entry$name]]
  entry$dir <- entry_dir
  entry$file <- rfile
  entry$hash <- unname(tools::md5sum(rfile))
  list(entry = entry, problems = character())
}

#' Select the entries to offer the LLM for this turn
#'
#' Scaling plan: (1) small library, return everything for the workflow;
#' (2) filter by current step; (3) search `summary` and `tags`. Only (1) is
#' implemented. The cut-over will be driven by
#' `cfg$library$max_tools_in_context`.
#' @noRd
select_entries <- function(entries, workflow) {
  keep <- vapply(entries, function(e) workflow %in% unlist(e$workflow), logical(1))
  entries[keep]
}

#' ellmer type for one parameter definition
#' @noRd
param_type <- function(p) {
  desc <- p$description %||% ""
  hint <- switch(
    p$source %||% "",
    raw_metadata_columns = " Must be a column name of the raw metadata.",
    sample_table_columns = " Must be a column name of the sample table.",
    condition_levels = " Must be one of the condition levels.",
    sample_ids = " Must be sample IDs.",
    ""
  )
  if (!is.null(p$values)) {
    hint <- paste0(" One of: ", paste(unlist(p$values), collapse = ", "), ".")
  }
  if (!is.null(p$default)) {
    hint <- paste0(hint, " Default: ", paste(unlist(p$default), collapse = ", "), ".")
  }
  desc <- paste0(desc, hint)
  required <- isTRUE(p$required)
  switch(
    p$type,
    string = ellmer::type_string(description = desc, required = required),
    integer = ellmer::type_integer(description = desc, required = required),
    number = ellmer::type_number(description = desc, required = required),
    boolean = ellmer::type_boolean(description = desc, required = required),
    string_list = ellmer::type_array(
      items = ellmer::type_string(), description = desc, required = required
    )
  )
}

#' Convert library entries to LLM tool definitions
#'
#' One tool per entry. Each tool, when called by the model, goes through
#' `run_step()`, which validates the call before anything runs.
#'
#' @param entries Named list of library entries.
#' @param state Project state environment.
#' @param session Shiny session, for notifications.
#' @noRd
library_as_tools <- function(entries, state, session = NULL) {
  tools <- lapply(entries, function(entry) {
    param_names <- names(entry$params)
    args <- rep(list(NULL), length(param_names))
    names(args) <- param_names
    fn_name <- entry$name
    body <- quote({
      params <- as.list(environment())
      params <- params[!vapply(params, is.null, logical(1))]
      res <- run_step(state, fn_name, params, session)
      to_json(res$for_llm)
    })
    fun <- rlang::new_function(
      args, body,
      env = rlang::env(
        environment(run_step),
        state = state, fn_name = fn_name, session = session
      )
    )
    needs <- if (length(entry$inputs) > 0) {
      paste0(" Needs: ", paste(entry$inputs, collapse = ", "), ".")
    } else {
      ""
    }
    ellmer::tool(
      fun,
      name = entry$name,
      description = paste0(trimws(entry$summary), needs),
      arguments = lapply(entry$params, param_type)
    )
  })

  state_tool <- ellmer::tool(
    function() to_json(describe_state(state)),
    name = "get_project_state",
    description = paste(
      "Report what exists in the project so far: loaded objects, metadata",
      "columns, the sample table, condition levels and completed steps.",
      "Call this when unsure what has been done or which values are valid."
    )
  )
  c(unname(tools), list(state_tool))
}

#' Promote a custom block to a library entry
#'
#' STUB. Takes reviewed custom code from a project, wraps it as a function,
#' and writes a new entry folder into the user library. The LLM drafts the
#' summary, tags and parameter descriptions; the user confirms before saving.
#' @noRd
promote_to_library <- function(custom_block, name, cfg) {
  rlang::abort("promote_to_library() is not implemented yet.")
}
