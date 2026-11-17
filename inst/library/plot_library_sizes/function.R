plot_library_sizes <- function(counts, sample_table) {
  st <- sample_table[sample_table$include, , drop = FALSE]
  df <- data.frame(
    sample_id = st$sample_id,
    condition = st$condition,
    millions = round(colSums(counts[, st$sample_id, drop = FALSE]) / 1e6, 2)
  )
  p <- ggplot2::ggplot(df, ggplot2::aes(x = sample_id, y = millions, fill = condition)) +
    ggplot2::geom_col() +
    ggplot2::labs(x = NULL, y = "Total reads (millions)") +
    ggplot2::theme_bw() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

  med <- stats::median(df$millions)
  low <- df$sample_id[df$millions < 0.5 * med]
  list(
    plot = p,
    table = df,
    summary = list(
      min_millions = min(df$millions),
      median_millions = med,
      max_millions = max(df$millions),
      samples_below_half_median = as.character(low)
    )
  )
}
