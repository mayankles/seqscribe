custom_state <- function(mode = "open") {
  cfg <- seqscribe:::load_config()
  cfg$paths$projects_dir <- tempfile("seqscribe_test_")
  cfg$mode <- mode
  lib <- seqscribe:::load_library(cfg)
  state <- seqscribe:::new_state(cfg, lib$entries)
  state$objects$counts <- matrix(1:6, nrow = 2, dimnames = list(c("g1", "g2"), c("a", "b", "c")))
  state
}

test_that("a cell sees project objects and records its output", {
  state <- custom_state()
  res <- seqscribe:::run_custom(state, "dim(counts)\nmessage('note')")
  expect_true(res$ok)
  expect_match(res$output, "\\[1\\] 2 3")
  expect_match(res$output, "note")
  expect_equal(res$step$type, "custom")
  expect_true(file.exists(file.path(state$project_dir, "results", res$step$id, "output.txt")))

  script <- readLines(file.path(state$project_dir, "scripts", "run_all.R"))
  expect_true(any(grepl("custom code", script)))
  expect_true("dim(counts)" %in% script)
  expect_false(any(grepl("custom.R", script, fixed = TRUE)))
  spec <- yaml::read_yaml(file.path(state$project_dir, "spec.yml"))
  expect_equal(spec$steps[[1]]$type, "custom")
  expect_match(spec$steps[[1]]$code, "dim\\(counts\\)")
})

test_that("variables persist between cells; plots are saved", {
  state <- custom_state()
  expect_true(seqscribe:::run_custom(state, "x <- colSums(counts)")$ok)
  res <- seqscribe:::run_custom(state, "plot(x)\nbarplot(x)")
  expect_true(res$ok)
  expect_length(res$step$plot, 2)
  expect_true(all(file.exists(file.path(state$project_dir, res$step$plot))))
})

test_that("errors and changes to project objects are not recorded", {
  state <- custom_state()
  err <- seqscribe:::run_custom(state, "y <- 1\nstop('boom')")
  expect_false(err$ok)
  expect_equal(err$error, "boom")
  expect_false(exists("y", envir = state$scratch, inherits = FALSE))

  clobber <- seqscribe:::run_custom(state, "counts <- counts * 2")
  expect_false(clobber$ok)
  expect_match(clobber$error, "can't change project objects \\(counts\\)")
  expect_equal(state$objects$counts[1, 1], 1L)
  expect_equal(seqscribe:::run_custom(state, "counts[1, 1]")$output, "[1] 1\n")

  expect_false(seqscribe:::run_custom(state, "   ")$ok)
  expect_length(Filter(seqscribe:::is_custom, state$steps), 1)
})

test_that("guided mode refuses custom code", {
  state <- custom_state(mode = "guided")
  res <- seqscribe:::run_custom(state, "1 + 1")
  expect_false(res$ok)
  expect_match(res$error, "guided mode")
})
