#' Project state and the step runner
#'
#' The state is a plain environment per session: the objects produced so far,
#' the list of completed steps and the project folder. Every function call,
#' whether it comes from the LLM or from the manual form, goes through
#' `run_step()`.
#' @name runner
#' @noRd
NULL

#' @noRd
new_state <- function(cfg, entries) {
  root <- path.expand(cfg$paths$projects_dir %||% "projects")
  project_dir <- file.path(root, format(Sys.time(), "project_%Y%m%d_%H%M%S"))
  for (sub in c("results", file.path("scripts", "library"), "report")) {
    dir.create(file.path(project_dir, sub), recursive = TRUE, showWarnings = FALSE)
  }
  state <- new.env(parent = emptyenv())
  state$cfg <- cfg
  state$entries <- entries
  state$objects <- list()
  state$derived_from <- list()
  state$steps <- list()
  state$project_dir <- normalizePath(project_dir)
  state$workflow <- cfg$workflows$default %||% "bulk_rnaseq"
  state
}

#' Allowed values for a parameter, given the current project state
#' @noRd
param_choices <- function(param, state) {
  if (!is.null(param$values)) return(as.character(unlist(param$values)))
  st <- state$objects$sample_table
  raw <- state$objects$raw_metadata
  switch(
    param$source %||% "",
    raw_metadata_columns = if (!is.null(raw)) setdiff(names(raw), "sample_id"),
    sample_table_columns = if (!is.null(st)) setdiff(names(st), c("sample_id", "include")),
    condition_levels = if (!is.null(st)) levels(factor(st$condition[st$include])),
    sample_ids = if (!is.null(raw)) raw$sample_id,
    NULL
  )
}

#' Validate and coerce a proposed call
#'
#' Rejects unknown functions and parameters, wrong types and values outside
#' the allowed set. Everything the LLM proposes goes through this.
#' @return list(params = cleaned list with defaults filled, problems = character)
#' @noRd
validate_call <- function(state, fn, params) {
  entry <- state$entries[[fn]]
  if (is.null(entry)) {
    return(list(params = list(), problems = paste0("Unknown function '", fn, "'.")))
  }
  problems <- character()
  unknown <- setdiff(names(params), names(entry$params))
  if (length(unknown) > 0) {
    problems <- c(problems, paste0(
      "Unknown parameter(s): ", paste(unknown, collapse = ", "),
      ". Allowed: ", paste(names(entry$params), collapse = ", "), "."
    ))
  }

  clean <- list()
  for (p in entry$params) {
    value <- params[[p$name]]
    if (is.character(value) && p$type != "string_list") value <- trimws(value[1])
    if (is.null(value) || identical(value, "") || length(value) == 0) value <- p$default
    if (is.null(value)) {
      if (isTRUE(p$required)) {
        problems <- c(problems, paste0("Missing required parameter '", p$name, "'."))
      }
      next
    }

    value <- switch(
      p$type,
      string = as.character(value)[1],
      integer = suppressWarnings(as.integer(round(as.numeric(value[1])))),
      number = suppressWarnings(as.numeric(value[1])),
      boolean = {
        if (is.logical(value)) value[1] else tolower(as.character(value[1])) %in% c("true", "yes", "1")
      },
      string_list = {
        v <- trimws(unlist(strsplit(as.character(unlist(value)), ",", fixed = TRUE)))
        v[nzchar(v)]
      }
    )
    if (length(value) == 0) next
    if (anyNA(value)) {
      problems <- c(problems, paste0("Parameter '", p$name, "' must be of type ", p$type, "."))
      next
    }

    if (p$type %in% c("integer", "number")) {
      if (!is.null(p$min) && value < p$min) {
        problems <- c(problems, paste0("'", p$name, "' must be at least ", p$min, "."))
      }
      if (!is.null(p$max) && value > p$max) {
        problems <- c(problems, paste0("'", p$name, "' must be at most ", p$max, "."))
      }
    }

    choices <- param_choices(p, state)
    if (!is.null(choices) && p$type %in% c("string", "string_list")) {
      # Forgive case differences, which small models often introduce.
      idx <- match(tolower(value), tolower(choices))
      value[!is.na(idx)] <- choices[idx[!is.na(idx)]]
      bad <- value[is.na(idx)]
      if (length(bad) > 0) {
        problems <- c(problems, paste0(
          "Invalid value for '", p$name, "': ", paste(bad, collapse = ", "),
          ". Allowed: ", paste(choices, collapse = ", "), "."
        ))
      }
    }
    clean[[p$name]] <- value
  }
  list(params = clean, problems = problems)
}

#' Run one library function as a project step
#'
#' @return list(ok, error, step, for_llm). `for_llm` is the only thing sent
#'   back to the model: a status plus the function's summary, never raw data.
#' @noRd
run_step <- function(state, fn, params = list(), session = NULL) {
  fail <- function(msg) {
    notify(session, paste0(fn, ": ", msg), type = "error")
    list(ok = FALSE, error = msg, for_llm = list(status = "error", message = msg))
  }

  entry <- state$entries[[fn]]
  checked <- validate_call(state, fn, params)
  if (length(checked$problems) > 0) return(fail(paste(checked$problems, collapse = " ")))
  params <- checked$params

  missing_inputs <- setdiff(entry$inputs, names(state$objects))
  if (length(missing_inputs) > 0) {
    producers <- vapply(missing_inputs, function(obj) {
      made_by <- names(Filter(function(e) obj %in% e$produces, state$entries))
      if (length(made_by) > 0) paste0(obj, " (run ", made_by[1], " first)") else obj
    }, "")
    return(fail(paste0("Missing input: ", paste(producers, collapse = "; "), ".")))
  }

  missing_pkgs <- entry$requires[!vapply(entry$requires, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_pkgs) > 0) {
    return(fail(paste0("R packages not installed: ", paste(missing_pkgs, collapse = ", "), ".")))
  }

  notify(session, paste0("Running ", fn, "..."))
  out <- tryCatch(
    do.call(entry$fun, c(state$objects[entry$inputs], params)),
    error = function(e) e
  )
  if (inherits(out, "error")) return(fail(conditionMessage(out)))

  step_id <- sprintf("%02d_%s", length(state$steps) + 1L, fn)
  step_dir <- file.path(state$project_dir, "results", step_id)
  dir.create(step_dir, recursive = TRUE, showWarnings = FALSE)

  plot_rel <- NULL
  if (!is.null(out$plot)) {
    plot_rel <- file.path("results", step_id, "plot.png")
    ggplot2::ggsave(file.path(state$project_dir, plot_rel), plot = out$plot,
                    width = 7, height = 5, dpi = 110)
  }
  table_rel <- NULL
  table_html <- NULL
  if (!is.null(out$table)) {
    table_rel <- file.path("results", step_id, "table.tsv")
    utils::write.table(out$table, file.path(state$project_dir, table_rel),
                       sep = "\t", quote = FALSE, row.names = FALSE)
    table_html <- as.character(knitr::kable(
      utils::head(out$table, 10), format = "html", digits = 3, row.names = FALSE,
      table.attr = 'class="table table-sm table-striped"'
    ))
  }

  # Store what the step produced. If it replaced an existing object, drop
  # everything derived from the old one, so no later step can use stale data.
  produced <- names(out$objects)
  replaced <- intersect(produced, names(state$objects))
  dropped <- setdiff(dependents(state$derived_from, replaced), produced)
  for (obj in produced) {
    # An object updated from itself (dds in run_deseq2) keeps its ancestry.
    kept <- if (obj %in% entry$inputs) state$derived_from[[obj]]
    state$derived_from[[obj]] <- union(setdiff(entry$inputs, obj), kept)
    state$objects[[obj]] <- out$objects[[obj]]
  }
  state$objects[dropped] <- NULL
  state$derived_from[dropped] <- NULL
  if (length(dropped) > 0) {
    notify(session, paste0(
      fn, " replaced ", paste(replaced, collapse = ", "), "; removed out-of-date: ",
      paste(dropped, collapse = ", "), "."
    ), type = "warning")
  }
  file.copy(entry$file,
            file.path(state$project_dir, "scripts", "library", paste0(fn, ".R")),
            overwrite = TRUE)

  step <- list(
    id = step_id,
    fn = fn,
    title = entry$title,
    workflow_step = entry$step,
    version = entry$version,
    hash = entry$hash,
    layer = entry$layer,
    params = params,
    summary = out$summary,
    invalidated = dropped,
    plot = plot_rel,
    table = table_rel,
    table_html = table_html,
    n_table_rows = if (!is.null(out$table)) nrow(out$table) else NULL,
    code = step_code(entry, params, names(out$objects)),
    methods = fill_template(entry$methods_text %||% "", params),
    time = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
  state$steps[[step_id]] <- step

  tryCatch({
    spec_write(state)
    writeLines(build_script(state), file.path(state$project_dir, "scripts", "run_all.R"))
  }, error = function(e) notify(session, paste("Could not save project files:", conditionMessage(e)), type = "warning"))

  for_llm <- list(status = "ok", step_id = step_id, result = out$summary)
  if (length(dropped) > 0) {
    for_llm$removed_objects <- as.list(dropped)
    for_llm$note <- paste(
      "These objects were out of date and have been removed.",
      "Rebuild them before any step that needs them."
    )
  }
  list(ok = TRUE, error = NULL, step = step, for_llm = for_llm)
}

#' Objects derived, directly or indirectly, from any of `objs`
#'
#' @param derived_from Named list: object name -> names of the objects it was
#'   made from.
#' @noRd
dependents <- function(derived_from, objs) {
  found <- character()
  repeat {
    hit <- vapply(derived_from, function(src) any(src %in% c(objs, found)), logical(1))
    new <- setdiff(names(derived_from)[hit], c(objs, found))
    if (length(new) == 0) break
    found <- c(found, new)
  }
  found
}

#' What the LLM is told about the project when it asks
#' @noRd
describe_state <- function(state) {
  st <- state$objects$sample_table
  raw <- state$objects$raw_metadata
  list(
    objects_available = names(state$objects),
    raw_metadata_columns = if (!is.null(raw)) setdiff(names(raw), "sample_id"),
    sample_table = if (!is.null(st)) list(
      columns = setdiff(names(st), c("sample_id", "include")),
      condition_levels = levels(factor(st$condition[st$include])),
      n_included = sum(st$include),
      excluded = st$sample_id[!st$include]
    ),
    completed_steps = lapply(unname(state$steps), function(s) {
      list(step_id = s$id, fn = s$fn, params = s$params)
    })
  )
}

#' Replace {{name}} placeholders with parameter values
#' @noRd
fill_template <- function(text, params) {
  text <- paste(trimws(text), collapse = " ")
  for (name in names(params)) {
    text <- gsub(paste0("{{", name, "}}"), paste(params[[name]], collapse = ", "), text, fixed = TRUE)
  }
  gsub("\\{\\{[^}]+\\}\\}", "none", text)
}

#' Show a notification if there is a session to show it in
#' @noRd
notify <- function(session, msg, type = "message") {
  if (is.null(session)) return(invisible())
  tryCatch(
    shiny::showNotification(msg, type = type, duration = if (type == "error") 10 else 3, session = session),
    error = function(e) NULL
  )
  invisible()
}
