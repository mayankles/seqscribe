build_dds <- function(counts, sample_table, min_count = 10) {
  st <- sample_table[sample_table$include, , drop = FALSE]
  covariates <- setdiff(names(st), c("sample_id", "condition", "include"))
  coldata <- droplevels(st[, c("condition", covariates), drop = FALSE])
  rownames(coldata) <- st$sample_id
  design <- stats::as.formula(paste("~", paste(c(covariates, "condition"), collapse = " + ")))

  cts <- counts[, st$sample_id, drop = FALSE]
  storage.mode(cts) <- "integer"
  dds <- DESeq2::DESeqDataSetFromMatrix(countData = cts, colData = coldata, design = design)

  n_before <- nrow(dds)
  smallest <- min(table(coldata$condition))
  keep <- rowSums(DESeq2::counts(dds) >= min_count) >= smallest
  dds <- dds[keep, ]

  list(
    objects = list(dds = dds),
    summary = list(
      design = paste(deparse(design), collapse = ""),
      n_samples = ncol(dds),
      genes_before_filter = n_before,
      genes_after_filter = nrow(dds),
      min_count = min_count,
      min_samples = as.integer(smallest)
    )
  )
}
