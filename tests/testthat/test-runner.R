test_state <- function() {
  cfg <- seqscribe:::load_config()
  cfg$paths$projects_dir <- tempfile("seqscribe_test_")
  lib <- seqscribe:::load_library(cfg)
  seqscribe:::new_state(cfg, lib$entries)
}

# Four samples, two groups; `batch` is confounded with `group`, `site` has a
# single value, `pair` is a usable covariate.
fake_inputs <- function(state) {
  ids <- paste0("s", 1:4)
  state$objects$raw_metadata <- data.frame(
    sample_id = ids,
    group = c("a", "a", "b", "b"),
    batch = c("x", "x", "y", "y"),
    site = "one",
    pair = c("p", "q", "p", "q"),
    stringsAsFactors = FALSE
  )
  state$objects$counts <- matrix(1L, nrow = 3, ncol = 4, dimnames = list(NULL, ids))
  state
}

test_that("dependents() follows chains of derived objects", {
  derived <- list(
    sample_table = c("raw_metadata", "counts"),
    dds = c("counts", "sample_table"),
    de_results = "dds"
  )
  expect_setequal(seqscribe:::dependents(derived, "sample_table"), c("dds", "de_results"))
  expect_setequal(seqscribe:::dependents(derived, "dds"), "de_results")
  expect_length(seqscribe:::dependents(derived, "de_results"), 0)
  expect_length(seqscribe:::dependents(list(), "counts"), 0)
})

test_that("a design that cannot be fitted is rejected and changes nothing", {
  state <- fake_inputs(test_state())

  ok <- seqscribe:::run_step(state, "set_sample_table",
                             list(condition_column = "group", covariates = "pair"))
  expect_true(ok$ok)

  confounded <- seqscribe:::run_step(state, "set_sample_table",
                                     list(condition_column = "group", covariates = "batch"))
  expect_false(confounded$ok)
  expect_match(confounded$error, "not full rank")

  constant <- seqscribe:::run_step(state, "set_sample_table",
                                   list(condition_column = "group", covariates = "site"))
  expect_false(constant$ok)
  expect_match(constant$error, "only one value")

  expect_length(state$steps, 1)
  expect_equal(names(state$objects$sample_table), c("sample_id", "condition", "pair", "include"))
})

test_that("replacing an object removes what was derived from it", {
  skip_if_not_installed("DESeq2")
  skip_if_not_installed("airway")
  state <- test_state()
  run <- function(fn, params = list()) seqscribe:::run_step(state, fn, params)

  run("load_demo_airway")
  run("set_sample_table", list(condition_column = "dex", reference_level = "untrt", covariates = "cell"))
  run("build_dds")
  first <- suppressMessages(run("run_deseq2", list(numerator = "trt", denominator = "untrt")))
  expect_true(first$ok)
  # Updating dds from itself keeps de_results and the link to the sample table.
  expect_length(first$step$invalidated, 0)
  expect_true(all(c("dds", "de_results") %in% names(state$objects)))

  changed <- run("set_sample_table", list(condition_column = "dex", reference_level = "untrt"))
  expect_true(changed$ok)
  expect_setequal(changed$step$invalidated, c("dds", "de_results"))
  expect_setequal(unlist(changed$for_llm$removed_objects), c("dds", "de_results"))
  expect_false(any(c("dds", "de_results") %in% names(state$objects)))

  stale <- run("plot_volcano")
  expect_false(stale$ok)
  expect_match(stale$error, "Missing input")
})
