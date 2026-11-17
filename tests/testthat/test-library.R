test_that("built-in library loads without problems", {
  cfg <- seqscribe:::load_config()
  lib <- seqscribe:::load_library(cfg)
  expect_length(lib$problems, 0)
  expect_true(all(c("load_demo_airway", "set_sample_table", "build_dds", "run_deseq2") %in% names(lib$entries)))
})

test_that("calls are validated before they run", {
  cfg <- seqscribe:::load_config()
  cfg$paths$projects_dir <- tempfile("seqscribe_test_")
  lib <- seqscribe:::load_library(cfg)
  state <- seqscribe:::new_state(cfg, lib$entries)

  bad_fn <- seqscribe:::validate_call(state, "no_such_function", list())
  expect_gt(length(bad_fn$problems), 0)

  bad_param <- seqscribe:::validate_call(state, "build_dds", list(min_count = "abc"))
  expect_gt(length(bad_param$problems), 0)

  out_of_range <- seqscribe:::validate_call(state, "build_dds", list(min_count = -5))
  expect_gt(length(out_of_range$problems), 0)

  defaults <- seqscribe:::validate_call(state, "build_dds", list())
  expect_length(defaults$problems, 0)
  expect_equal(defaults$params$min_count, 10L)

  missing_input <- seqscribe:::run_step(state, "build_dds", list())
  expect_false(missing_input$ok)
  expect_match(missing_input$error, "Missing input")
})
