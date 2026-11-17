#' Report builder
#'
#' Stitches the selected steps into an R Markdown report. Each step becomes a
#' block: title, methods text, the code that ran, and its figure or table.
#' @name report
#' @noRd
NULL

#' @param state Project state.
#' @param step_ids IDs of the steps to include, in order.
#' @return list(rmd = path, html = path or NULL, message)
#' @noRd
build_report <- function(state, step_ids) {
  steps <- state$steps[intersect(names(state$steps), step_ids)]
  if (length(steps) == 0) return(list(rmd = NULL, html = NULL, message = "No steps selected."))

  header <- readLines(pkg_file("templates", "report_header.Rmd"), warn = FALSE)
  header <- gsub("{{report_title}}", "seqscribe analysis report", header, fixed = TRUE)

  body <- character()
  for (s in steps) {
    block <- c("", paste0("## ", s$title), "", s$methods, "",
               "```{r, eval=FALSE}", s$code, "```", "")
    if (!is.null(s$plot)) {
      block <- c(block, paste0("![](", file.path("..", s$plot), ")"), "")
    }
    if (!is.null(s$table)) {
      block <- c(
        block,
        "```{r, echo=FALSE}",
        paste0("tbl <- utils::read.delim(\"", file.path("..", s$table), "\", check.names = FALSE)"),
        "knitr::kable(utils::head(tbl, 20), digits = 3)",
        "```",
        if (isTRUE(s$n_table_rows > 20)) paste0("First 20 of ", s$n_table_rows, " rows; full table in `", s$table, "`."),
        ""
      )
    }
    body <- c(body, block)
  }
  footer <- c("", "## Session information", "", "```{r, echo=FALSE}", "sessionInfo()", "```")

  rmd <- file.path(state$project_dir, "report", "report.Rmd")
  writeLines(c(header, body, footer), rmd)

  if (!requireNamespace("rmarkdown", quietly = TRUE) || !rmarkdown::pandoc_available()) {
    return(list(rmd = rmd, html = NULL,
                message = "Report source written. Rendering needs the rmarkdown package and pandoc."))
  }
  html <- tryCatch(
    rmarkdown::render(rmd, quiet = TRUE, envir = new.env(parent = globalenv())),
    error = function(e) e
  )
  if (inherits(html, "error")) {
    return(list(rmd = rmd, html = NULL, message = paste("Rendering failed:", conditionMessage(html))))
  }
  list(rmd = rmd, html = html, message = "Report rendered.")
}
