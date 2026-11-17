run_deseq2 <- function(dds, numerator, denominator, alpha = 0.05) {
  if (identical(numerator, denominator)) {
    stop("numerator and denominator must be different condition levels.")
  }
  dds <- DESeq2::DESeq(dds, quiet = TRUE)
  res <- DESeq2::results(dds, contrast = c("condition", numerator, denominator), alpha = alpha)
  df <- as.data.frame(res)
  df <- cbind(gene_id = rownames(df), df, stringsAsFactors = FALSE)
  rownames(df) <- NULL
  df <- df[order(df$padj, na.last = TRUE), ]

  sig <- !is.na(df$padj) & df$padj < alpha
  top <- utils::head(df[sig, c("gene_id", "log2FoldChange", "padj")], 10)
  list(
    objects = list(dds = dds, de_results = df),
    table = df,
    summary = list(
      contrast = paste(numerator, "vs", denominator),
      design = paste(deparse(DESeq2::design(dds)), collapse = ""),
      genes_tested = sum(!is.na(df$padj)),
      significant_up = sum(sig & df$log2FoldChange > 0),
      significant_down = sum(sig & df$log2FoldChange < 0),
      alpha = alpha,
      top_genes = lapply(seq_len(nrow(top)), function(i) list(
        gene_id = top$gene_id[i],
        log2FoldChange = round(top$log2FoldChange[i], 2),
        padj = signif(top$padj[i], 3)
      ))
    )
  )
}
