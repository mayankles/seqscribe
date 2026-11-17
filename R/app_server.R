#' App server
#'
#' Wires together the library, the project state, the chat loop and the
#' three panels. All analysis goes through `run_step()`, whether the request
#' comes from the assistant or from the manual form.
#'
#' @noRd
app_server <- function(input, output, session, cfg) {
  lib <- load_library(cfg)
  workflow <- yaml::read_yaml(
    pkg_file("workflows", paste0(cfg$workflows$default %||% "bulk_rnaseq", ".yml"))
  )
  entries <- select_entries(lib$entries, workflow$name)
  state <- new_state(cfg, entries)

  # Bumped whenever the project changes, so outputs know to redraw.
  refresh <- shiny::reactiveVal(0)
  bump <- function() shiny::isolate(refresh(refresh() + 1))

  # Serve the project folder so plots and the report can be shown.
  # A relative prefix keeps this working behind an HPC portal's sub-path.
  prefix <- paste0("project", paste(sample(0:9, 8, replace = TRUE), collapse = ""))
  shiny::addResourcePath(prefix, state$project_dir)
  session$onSessionEnded(function() shiny::removeResourcePath(prefix))

  # ---- LLM connection ------------------------------------------------------
  health <- llm_health_check(cfg)
  chat <- NULL
  chat_error <- NULL
  if (health$ok) {
    chat <- tryCatch({
      client <- llm_client(cfg, system_prompt(cfg, workflow))
      for (tool in library_as_tools(entries, state, session)) client$register_tool(tool)
      client
    }, error = function(e) {
      chat_error <<- conditionMessage(e)
      NULL
    })
  }

  output$status_banner <- shiny::renderUI({
    msgs <- list()
    if (!health$ok || !health$model_found) {
      msgs <- c(msgs, list(shiny::div(class = "alert alert-warning py-2 mb-2", health$message)))
    }
    if (!is.null(chat_error)) {
      msgs <- c(msgs, list(shiny::div(
        class = "alert alert-danger py-2 mb-2",
        paste("Could not set up the assistant:", chat_error)
      )))
    }
    if (length(lib$problems) > 0) {
      msgs <- c(msgs, list(shiny::div(
        class = "alert alert-warning py-2 mb-2",
        shiny::strong("Library entries skipped: "), paste(lib$problems, collapse = "; ")
      )))
    }
    shiny::tagList(msgs)
  })

  # ---- Chat loop -----------------------------------------------------------
  shiny::observeEvent(input$chat_user_input, {
    if (is.null(chat)) {
      shinychat::chat_append("chat", paste(
        "The assistant is not connected, so I can't act on that.",
        "You can still run functions from the manual form on the left."
      ))
      return()
    }
    response <- if (isTRUE(cfg$llm$stream)) {
      chat$stream_async(input$chat_user_input)
    } else {
      chat$chat_async(input$chat_user_input)
    }
    done <- shinychat::chat_append("chat", response)
    promises::then(
      done,
      onFulfilled = function(value) bump(),
      onRejected = function(err) {
        bump()
        notify(session, paste("Assistant error:", conditionMessage(err)), type = "error")
      }
    )
  })

  # ---- Left panel: workflow map and manual form ----------------------------
  output$steps_nav <- shiny::renderUI({
    refresh()
    done_steps <- unique(vapply(state$steps, function(s) s$workflow_step, ""))
    items <- lapply(workflow$steps, function(ws) {
      fns <- names(Filter(function(e) identical(e$step, ws$id), entries))
      is_done <- ws$id %in% done_steps
      shiny::div(
        class = "mb-3",
        shiny::div(
          shiny::span(class = if (is_done) "badge bg-success me-1" else "badge bg-secondary me-1",
                      if (is_done) "done" else "to do"),
          shiny::strong(ws$title)
        ),
        shiny::div(class = "small text-muted", ws$description),
        if (length(fns) > 0) shiny::div(class = "small", shiny::code(paste(fns, collapse = ", ")))
      )
    })
    shiny::tagList(items)
  })

  shiny::updateSelectInput(session, "manual_fn", choices = names(entries))

  output$manual_params <- shiny::renderUI({
    refresh()
    entry <- entries[[input$manual_fn %||% ""]]
    if (is.null(entry)) return(NULL)
    if (length(entry$params) == 0) return(shiny::div(class = "small text-muted", "No parameters."))
    lapply(entry$params, function(p) {
      choices <- param_choices(p, state)
      hint <- if (!is.null(choices)) {
        paste("one of:", paste(choices, collapse = ", "))
      } else if (!is.null(p$default)) {
        paste("default:", paste(unlist(p$default), collapse = ", "))
      } else {
        ""
      }
      shiny::textInput(
        paste0("mp_", entry$name, "_", p$name),
        label = paste0(p$name, if (isTRUE(p$required)) " *" else ""),
        placeholder = hint
      )
    })
  })

  shiny::observeEvent(input$manual_run, {
    entry <- entries[[input$manual_fn %||% ""]]
    if (is.null(entry)) return()
    params <- list()
    for (p in entry$params) {
      value <- input[[paste0("mp_", entry$name, "_", p$name)]]
      if (!is.null(value) && nzchar(trimws(value))) params[[p$name]] <- value
    }
    run_step(state, entry$name, params, session)
    bump()
  })

  # ---- Centre panel --------------------------------------------------------
  output$results_feed <- shiny::renderUI({
    refresh()
    if (length(state$steps) == 0) {
      return(shiny::div(class = "text-muted p-3", "Nothing has been run yet. Results appear here, newest first."))
    }
    cards <- lapply(rev(unname(state$steps)), function(s) {
      bslib::card(
        class = "mb-3",
        bslib::card_header(paste0(s$id, " · ", s$title)),
        shiny::pre(class = "small mb-2", paste(s$code, collapse = "\n")),
        if (!is.null(s$plot)) shiny::img(src = paste0(prefix, "/", s$plot), style = "max-width: 100%; height: auto;"),
        if (!is.null(s$table_html)) shiny::div(style = "overflow-x: auto;", shiny::HTML(s$table_html)),
        if (isTRUE(s$n_table_rows > 10)) shiny::div(class = "small text-muted", paste0("First 10 of ", s$n_table_rows, " rows. Full table: ", s$table)),
        shiny::tags$details(
          shiny::tags$summary(class = "small", "Summary sent to the assistant"),
          shiny::pre(class = "small", as.character(jsonlite::toJSON(s$summary, auto_unbox = TRUE, pretty = TRUE, null = "null", force = TRUE)))
        )
      )
    })
    shiny::tagList(
      shiny::div(class = "small text-muted mb-2", paste("Project folder:", state$project_dir)),
      cards
    )
  })

  output$sample_table <- shiny::renderTable({
    refresh()
    st <- state$objects$sample_table %||% state$objects$raw_metadata
    if (is.null(st)) return(data.frame(Note = "No data loaded yet."))
    st
  })

  output$script <- shiny::renderText({
    refresh()
    paste(build_script(state), collapse = "\n")
  })

  # ---- Report --------------------------------------------------------------
  shiny::observe({
    refresh()
    ids <- names(state$steps)
    labels <- vapply(state$steps, function(s) paste0(s$id, " · ", s$title), "")
    shiny::updateCheckboxGroupInput(
      session, "report_steps",
      choices = stats::setNames(ids, labels),
      selected = union(intersect(shiny::isolate(input$report_steps), ids), utils::tail(ids, 1))
    )
  })

  report_result <- shiny::reactiveVal(NULL)
  shiny::observeEvent(input$build_report, {
    notify(session, "Building report...")
    report_result(build_report(state, input$report_steps))
  })
  output$report_status <- shiny::renderUI({
    res <- report_result()
    if (is.null(res)) return(NULL)
    shiny::div(
      class = "mt-3",
      shiny::p(res$message),
      if (!is.null(res$html)) shiny::a(
        "Open report", target = "_blank",
        href = paste0(prefix, "/report/", basename(res$html), "?t=", as.integer(Sys.time()))
      ),
      if (!is.null(res$rmd)) shiny::div(class = "small text-muted", paste("Source:", res$rmd))
    )
  })
}
