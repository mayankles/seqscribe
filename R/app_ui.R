#' App UI
#'
#' Three panels: the workflow map on the left, the project (results, sample
#' table, script, report) in the centre, the assistant on the right.
#'
#' @param cfg Configuration list from [load_config()].
#' @noRd
app_ui <- function(cfg) {
  greeting <- paste(
    "**Hi.** Tell me what to do in plain language. For the demo, try these in order:\n\n",
    "1. *Load the airway demo data*\n",
    "2. *Use dex as the condition with untrt as the reference, and adjust for cell line*\n",
    "3. *Build the dataset, then show me a PCA coloured by cell*\n",
    "4. *Run the differential expression for treated versus untreated*\n",
    "5. *Make a volcano plot*"
  )

  bslib::page_fillable(
    title = "seqscribe",
    padding = 10,
    shiny::uiOutput("status_banner"),
    bslib::layout_columns(
      col_widths = c(3, 5, 4),
      fill = TRUE,
      bslib::card(
        bslib::card_header("Workflow"),
        shiny::uiOutput("steps_nav"),
        bslib::accordion(
          open = FALSE,
          bslib::accordion_panel(
            "Run a function manually",
            shiny::selectInput("manual_fn", "Function", choices = NULL),
            shiny::uiOutput("manual_params"),
            shiny::actionButton("manual_run", "Run", class = "btn-primary btn-sm")
          )
        )
      ),
      bslib::navset_card_tab(
        title = "Project",
        # The plain div stops the fill layout from squashing the result cards.
        bslib::nav_panel("Results", shiny::div(shiny::uiOutput("results_feed"))),
        bslib::nav_panel("Sample table", shiny::tableOutput("sample_table")),
        bslib::nav_panel("Script", shiny::verbatimTextOutput("script")),
        bslib::nav_panel(
          "Report",
          shiny::checkboxGroupInput("report_steps", "Steps to include", choices = NULL),
          shiny::actionButton("build_report", "Build report", class = "btn-primary btn-sm"),
          shiny::uiOutput("report_status")
        )
      ),
      bslib::card(
        bslib::card_header("Assistant"),
        shinychat::chat_ui("chat", greeting = greeting, fill = TRUE,
                           # No file attachments: the LLM never sees raw data.
                           allow_attachments = FALSE)
      )
    )
  )
}
