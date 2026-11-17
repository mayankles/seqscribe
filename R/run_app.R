#' Launch the seqscribe workbench
#'
#' Loads the configuration, then starts the Shiny app.
#'
#' @param config_file Optional path to a config file. Defaults to the packaged
#'   `inst/config/config.yml`, overlaid with `config.local.yml` in the working
#'   directory if present.
#' @param ... Passed to [shiny::shinyApp()].
#' @export
run_app <- function(config_file = NULL, ...) {
  cfg <- load_config(config_file)
  shiny::shinyApp(
    ui = app_ui(cfg),
    server = function(input, output, session) app_server(input, output, session, cfg),
    ...
  )
}
