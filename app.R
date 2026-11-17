# Launcher for local use and for HPC "run a Shiny app" portals.
# Select a config profile with the R_CONFIG_ACTIVE environment variable
# (e.g. "local" or "hpc"); see inst/config/config.yml.
if (requireNamespace("seqscribe", quietly = TRUE)) {
  seqscribe::run_app()
} else {
  pkgload::load_all(".")
  run_app()
}

