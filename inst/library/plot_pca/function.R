plot_pca <- function(dds, color_by = "condition", shape_by = NULL, ntop = 500,
                     pc_x = 1, pc_y = 2, label_samples = FALSE, ellipses = FALSE,
                     n_loadings = 0, scale = FALSE) {
  if (pc_x == pc_y) stop("pc_x and pc_y must be different components.")

  # Same gene selection as DESeq2::plotPCA: the ntop most variable genes.
  vsd <- DESeq2::vst(dds, blind = TRUE)
  mat <- SummarizedExperiment::assay(vsd)
  rv <- apply(mat, 1, stats::var)
  keep <- order(rv, decreasing = TRUE)[seq_len(min(ntop, length(rv)))]
  mat <- mat[keep, , drop = FALSE]
  if (scale) mat <- mat[rv[keep] > 0, , drop = FALSE]

  pca <- stats::prcomp(t(mat), center = TRUE, scale. = scale)
  n_pcs <- ncol(pca$x)
  if (max(pc_x, pc_y) > n_pcs) {
    stop("Only ", n_pcs, " components are available for ", nrow(pca$x),
         " samples; choose pc_x and pc_y up to ", n_pcs, ".")
  }
  pct <- round(100 * pca$sdev^2 / sum(pca$sdev^2), 1)
  px <- paste0("PC", pc_x)
  py <- paste0("PC", pc_y)

  coldata <- as.data.frame(SummarizedExperiment::colData(dds))
  groups <- unique(c(color_by, shape_by))
  coords <- data.frame(sample_id = colnames(dds), x = pca$x[, pc_x], y = pca$x[, pc_y])
  for (g in groups) coords[[g]] <- coldata[[g]]

  mapping <- if (is.null(shape_by)) {
    ggplot2::aes(x = x, y = y, colour = !!rlang::sym(color_by))
  } else {
    ggplot2::aes(x = x, y = y, colour = !!rlang::sym(color_by), shape = !!rlang::sym(shape_by))
  }
  p <- ggplot2::ggplot(coords, mapping) +
    ggplot2::geom_point(size = 3) +
    ggplot2::labs(x = paste0(px, " (", pct[pc_x], "%)"), y = paste0(py, " (", pct[pc_y], "%)")) +
    ggplot2::theme_bw()

  notes <- character()
  if (ellipses) {
    sizes <- table(coords[[color_by]])
    big <- names(sizes)[sizes >= 3]
    if (length(big) < length(sizes)) {
      notes <- c(notes, paste0("No ellipse for groups with fewer than 3 samples: ",
                               paste(setdiff(names(sizes), big), collapse = ", ")))
    }
    if (length(big) > 0) {
      p <- p + ggplot2::stat_ellipse(
        data = coords[coords[[color_by]] %in% big, , drop = FALSE],
        mapping = ggplot2::aes(x = x, y = y, colour = !!rlang::sym(color_by), group = !!rlang::sym(color_by)),
        inherit.aes = FALSE, type = "norm", level = 0.95
      )
    }
  }
  if (label_samples) {
    p <- p + ggrepel::geom_text_repel(ggplot2::aes(label = sample_id),
                                      size = 3, show.legend = FALSE)
  }

  # Genes with the largest loadings on the two plotted components.
  rot <- pca$rotation[, c(pc_x, pc_y), drop = FALSE]
  top_loadings <- function(pc, n = 5) {
    v <- pca$rotation[, pc]
    idx <- order(abs(v), decreasing = TRUE)[seq_len(min(n, length(v)))]
    lapply(idx, function(i) list(gene_id = rownames(pca$rotation)[i], loading = round(unname(v[i]), 3)))
  }
  if (n_loadings > 0) {
    idx <- order(sqrt(rowSums(rot^2)), decreasing = TRUE)[seq_len(min(n_loadings, nrow(rot)))]
    arrows <- data.frame(gene_id = rownames(rot)[idx], xend = rot[idx, 1], yend = rot[idx, 2])
    # Stretch the arrows to about 80% of the range of the sample scores.
    stretch <- 0.8 * max(abs(c(coords$x, coords$y))) / max(abs(c(arrows$xend, arrows$yend)))
    arrows$xend <- arrows$xend * stretch
    arrows$yend <- arrows$yend * stretch
    p <- p +
      ggplot2::geom_segment(
        data = arrows, ggplot2::aes(x = 0, y = 0, xend = xend, yend = yend),
        inherit.aes = FALSE, colour = "red3", linewidth = 0.4,
        arrow = grid::arrow(length = grid::unit(0.015, "npc"))
      ) +
      ggrepel::geom_text_repel(
        data = arrows, ggplot2::aes(x = xend, y = yend, label = gene_id),
        inherit.aes = FALSE, colour = "red3", size = 2.5, segment.alpha = 0.3
      )
  }

  # How much of each plotted PC is explained by each sample-table variable.
  vars <- setdiff(names(coldata), "sizeFactor")
  r2 <- function(values, v) {
    tryCatch(round(summary(stats::lm(values ~ factor(coldata[[v]])))$r.squared, 2),
             error = function(e) NA)
  }
  explained <- lapply(vars, function(v) {
    stats::setNames(list(v, r2(coords$x, v), r2(coords$y, v)), c("variable", px, py))
  })

  out <- coords
  names(out)[names(out) == "x"] <- px
  names(out)[names(out) == "y"] <- py
  list(
    plot = p,
    table = out,
    summary = list(
      components = c(px, py),
      percent_var = stats::setNames(as.list(pct[c(pc_x, pc_y)]), c(px, py)),
      percent_var_first_pcs = stats::setNames(as.list(utils::head(pct, 5)), paste0("PC", seq_len(min(5, n_pcs)))),
      genes_used = nrow(mat),
      scaled = scale,
      variance_explained_by_variable = explained,
      top_loading_genes = stats::setNames(list(top_loadings(pc_x), top_loadings(pc_y)), c(px, py)),
      notes = notes
    )
  )
}
