plot_volcano <- function(de_results, alpha = 0.05, lfc_threshold = 1, label_top = 5,
                         label_direction = "both") {
  df <- de_results[!is.na(de_results$padj), ]
  df$status <- "not significant"
  df$status[df$padj < alpha & df$log2FoldChange >= lfc_threshold] <- "up"
  df$status[df$padj < alpha & df$log2FoldChange <= -lfc_threshold] <- "down"
  df$status <- factor(df$status, levels = c("down", "not significant", "up"))
  df$neg_log10_padj <- -log10(pmax(df$padj, 1e-300))

  # Label with symbols when an annotation step has added them, else gene IDs.
  df$label <- df$gene_id
  if ("symbol" %in% names(df)) {
    has_symbol <- !is.na(df$symbol) & nzchar(df$symbol)
    df$label[has_symbol] <- df$symbol[has_symbol]
  }
  # The label_top most significant genes in each chosen direction.
  directions <- switch(label_direction, up = "up", down = "down", both = c("up", "down"),
                       stop("label_direction must be one of: both, up, down."))
  top_in <- function(d) {
    h <- df[df$status == d, , drop = FALSE]
    utils::head(h[order(h$padj), , drop = FALSE], label_top)
  }
  labelled <- do.call(rbind, lapply(directions, top_in))

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
  if (nrow(labelled) > 0) {
    p <- p + ggrepel::geom_text_repel(
      data = labelled, ggplot2::aes(label = label),
      size = 3, colour = "black", max.overlaps = Inf, min.segment.length = 0,
      segment.colour = "grey40", show.legend = FALSE
    )
  }

  list(
    plot = p,
    summary = list(
      n_up = sum(df$status == "up"),
      n_down = sum(df$status == "down"),
      alpha = alpha,
      lfc_threshold = lfc_threshold,
      labelled_genes = stats::setNames(
        lapply(directions, function(d) as.character(labelled$label[labelled$status == d])),
        directions
      )
    )
  )
}
