plot_sample_correlation <- function(dds) {
  vsd <- DESeq2::vst(dds, blind = TRUE)
  cm <- stats::cor(SummarizedExperiment::assay(vsd))
  ord <- stats::hclust(stats::as.dist(1 - cm))$order
  ids <- colnames(cm)[ord]
  long <- data.frame(
    sample_a = factor(rep(colnames(cm), each = nrow(cm)), levels = ids),
    sample_b = factor(rep(rownames(cm), times = ncol(cm)), levels = ids),
    correlation = as.vector(cm)
  )
  p <- ggplot2::ggplot(long, ggplot2::aes(x = sample_a, y = sample_b, fill = correlation)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_viridis_c() +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_bw() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

  diag(cm) <- NA
  mean_cor <- round(rowMeans(cm, na.rm = TRUE), 4)
  list(
    plot = p,
    table = data.frame(sample_id = names(mean_cor), mean_correlation = unname(mean_cor)),
    summary = list(
      lowest_pairwise = round(min(cm, na.rm = TRUE), 4),
      highest_pairwise = round(max(cm, na.rm = TRUE), 4),
      sample_with_lowest_mean_correlation = names(mean_cor)[which.min(mean_cor)],
      its_mean_correlation = unname(min(mean_cor))
    )
  )
}
