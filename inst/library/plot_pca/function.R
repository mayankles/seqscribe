plot_pca <- function(dds, color_by = "condition", shape_by = NULL, ntop = 500) {
  vsd <- DESeq2::vst(dds, blind = TRUE)
  groups <- unique(c(color_by, shape_by))
  coords <- DESeq2::plotPCA(vsd, intgroup = groups, ntop = ntop, returnData = TRUE)
  pct <- round(100 * attr(coords, "percentVar"), 1)

  mapping <- if (is.null(shape_by)) {
    ggplot2::aes(x = PC1, y = PC2, colour = !!rlang::sym(color_by))
  } else {
    ggplot2::aes(x = PC1, y = PC2, colour = !!rlang::sym(color_by),
                 shape = !!rlang::sym(shape_by))
  }
  p <- ggplot2::ggplot(coords, mapping) +
    ggplot2::geom_point(size = 3) +
    ggplot2::labs(x = paste0("PC1 (", pct[1], "%)"), y = paste0("PC2 (", pct[2], "%)")) +
    ggplot2::theme_bw()

  # How much of each PC is explained by each sample-table variable (R squared).
  coldata <- as.data.frame(SummarizedExperiment::colData(dds))
  vars <- setdiff(names(coldata), "sizeFactor")
  explained <- lapply(vars, function(v) {
    r2 <- function(pc) {
      tryCatch(
        round(summary(stats::lm(coords[[pc]] ~ factor(coldata[[v]])))$r.squared, 2),
        error = function(e) NA
      )
    }
    list(variable = v, r2_pc1 = r2("PC1"), r2_pc2 = r2("PC2"))
  })

  out <- coords[, c("name", "PC1", "PC2", groups), drop = FALSE]
  names(out)[1] <- "sample_id"
  list(
    plot = p,
    table = out,
    summary = list(
      percent_var_pc1 = pct[1],
      percent_var_pc2 = pct[2],
      variance_explained_by_variable = explained
    )
  )
}
