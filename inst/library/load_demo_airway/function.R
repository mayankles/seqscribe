load_demo_airway <- function() {
  env <- new.env()
  utils::data("airway", package = "airway", envir = env)
  se <- env$airway
  counts <- SummarizedExperiment::assay(se, "counts")
  meta <- as.data.frame(SummarizedExperiment::colData(se))
  ids <- rownames(meta)
  meta <- as.data.frame(lapply(meta, as.character), stringsAsFactors = FALSE)
  meta <- cbind(sample_id = ids, meta, stringsAsFactors = FALSE)
  rownames(meta) <- NULL

  cols <- setdiff(names(meta), "sample_id")
  col_summary <- lapply(cols, function(col) {
    vals <- unique(meta[[col]])
    list(column = col, n_unique = length(vals), example_values = utils::head(vals, 6))
  })

  list(
    objects = list(counts = counts, raw_metadata = meta),
    table = meta,
    summary = list(
      n_samples = ncol(counts),
      n_genes = nrow(counts),
      metadata_columns = col_summary,
      next_step = "Choose the condition column and any covariates with set_sample_table."
    )
  )
}
