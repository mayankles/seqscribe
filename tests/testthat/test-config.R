test_that("packaged config loads and has the expected sections", {
  cfg <- seqscribe:::load_config()
  expect_true(all(c("llm", "paths", "library", "mode", "executor", "safety") %in% names(cfg)))
  expect_false(isTRUE(cfg$safety$send_raw_data_to_llm))
  expect_match(cfg$llm$base_url, "^http")
})

test_that("packaged YAML files parse", {
  files <- list.files(
    system.file(package = "seqscribe"),
    pattern = "\\.ya?ml$", recursive = TRUE, full.names = TRUE
  )
  expect_gt(length(files), 0)
  for (f in files) expect_no_error(yaml::read_yaml(f))
})
