demo_state <- function() {
  skip_if_not_installed("DESeq2")
  skip_if_not_installed("airway")
  skip_if_not_installed("ggrepel")
  cfg <- seqscribe:::load_config()
  cfg$paths$projects_dir <- tempfile("seqscribe_test_")
  lib <- seqscribe:::load_library(cfg)
  state <- seqscribe:::new_state(cfg, lib$entries)
  seqscribe:::run_step(state, "load_demo_airway")
  seqscribe:::run_step(state, "set_sample_table",
                       list(condition_column = "dex", reference_level = "untrt", covariates = "cell"))
  seqscribe:::run_step(state, "build_dds")
  state
}

test_that("plot_pca defaults match DESeq2's plotPCA", {
  state <- demo_state()
  res <- suppressMessages(seqscribe:::run_step(state, "plot_pca"))
  expect_true(res$ok)
  expect_equal(res$step$summary$components, c("PC1", "PC2"))
  vsd <- DESeq2::vst(state$objects$dds, blind = TRUE)
  ref <- suppressMessages(DESeq2::plotPCA(vsd, intgroup = "condition", returnData = TRUE))
  expect_equal(unname(unlist(res$step$summary$percent_var)),
               round(100 * attr(ref, "percentVar"), 1))
})

test_that("plot_pca options run and are checked", {
  state <- demo_state()
  run <- function(params) suppressMessages(seqscribe:::run_step(state, "plot_pca", params))

  res <- run(list(color_by = "cell", pc_x = 2, pc_y = 3, label_samples = TRUE,
                  ellipses = TRUE, n_loadings = 8, scale = TRUE))
  expect_true(res$ok)
  expect_equal(res$step$summary$components, c("PC2", "PC3"))
  expect_true(res$step$summary$scaled)
  expect_length(res$step$summary$top_loading_genes$PC3, 5)
  # cell lines have 2 samples each, too few for an ellipse
  expect_match(res$step$summary$notes, "fewer than 3 samples")

  expect_true(run(list(ellipses = TRUE))$ok)
  expect_match(run(list(pc_x = 1, pc_y = 9))$error, "Only 8 components")
  expect_match(run(list(pc_x = 2, pc_y = 2))$error, "must be different")
})

test_that("plot_volcano labels the most significant genes", {
  state <- demo_state()
  suppressMessages(seqscribe:::run_step(state, "run_deseq2", list(numerator = "trt", denominator = "untrt")))
  labels <- function(params) {
    res <- seqscribe:::run_step(state, "plot_volcano", params)
    expect_true(res$ok)
    res$step$summary$labelled_genes
  }

  # Default: top 5 up and top 5 down.
  both <- labels(list())
  expect_named(both, c("up", "down"))
  expect_length(both$up, 5)
  expect_length(both$down, 5)
  expect_equal(both$up[1], "ENSG00000152583")
  de <- state$objects$de_results
  expect_true(all(de$log2FoldChange[match(both$down, de$gene_id)] < 0))

  up_only <- labels(list(label_top = 3, label_direction = "up"))
  expect_named(up_only, "up")
  expect_length(up_only$up, 3)
  expect_length(labels(list(label_top = 0))$up, 0)

  bad <- seqscribe:::run_step(state, "plot_volcano", list(label_direction = "sideways"))
  expect_match(bad$error, "Allowed: both, up, down")

  # Symbols are used when the results carry them.
  state$objects$de_results$symbol <- paste0("SYM", seq_len(nrow(state$objects$de_results)))
  expect_true(all(grepl("^SYM", unlist(labels(list(label_top = 3))))))
})
