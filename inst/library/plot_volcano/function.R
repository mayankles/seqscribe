plot_volcano <- function(de_results, alpha = 0.05, lfc_threshold = 1) {
  df <- de_results[!is.na(de_results$padj), ]
  df$status <- "not significant"
  df$status[df$padj < alpha & df$log2FoldChange >= lfc_threshold] <- "up"
  df$status[df$padj < alpha & df$log2FoldChange <= -lfc_threshold] <- "down"
  df$status <- factor(df$status, levels = c("down", "not significant", "up"))
  df$neg_log10_padj <- -log10(pmax(df$padj, 1e-300))

  p <- ggplot2::ggplot(df, ggplot2::aes(x = log2FoldChange, y = neg_log10_padj, colour = status)) +
    ggplot2::geom_point(size = 0.8, alpha = 0.6) +
    ggplot2::scale_colour_manual(
      values = c(down = "#2166ac", `not significant` = "grey70", up = "#b2182b"),
      drop = FALSE
    ) +
    ggplot2::geom_vline(xintercept = c(-lfc_threshold, lfc_threshold), linetype = "dashed") +
    ggplot2::geom_hline(yintercept = -log10(alpha), linetype = "dashed") +
    ggplot2::labs(x = "log2 fold change", y = "-log10 adjusted p-value", colour = NULL) +
    ggplot2::theme_bw()

  list(
    plot = p,
    summary = list(
      n_up = sum(df$status == "up"),
      n_down = sum(df$status == "down"),
      alpha = alpha,
      lfc_threshold = lfc_threshold
    )
  )
}
