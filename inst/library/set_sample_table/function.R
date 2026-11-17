set_sample_table <- function(raw_metadata, counts, condition_column,
                             reference_level = NULL, covariates = NULL,
                             exclude_samples = NULL) {
  covariates <- setdiff(covariates, condition_column)
  missing_ids <- setdiff(raw_metadata$sample_id, colnames(counts))
  if (length(missing_ids) > 0) {
    stop("These samples are not columns of the counts matrix: ",
         paste(missing_ids, collapse = ", "))
  }

  condition <- factor(raw_metadata[[condition_column]])
  if (!is.null(reference_level)) {
    if (!reference_level %in% levels(condition)) {
      stop("reference_level '", reference_level, "' is not a value of ",
           condition_column, ". Values: ", paste(levels(condition), collapse = ", "))
    }
    condition <- stats::relevel(condition, ref = reference_level)
  }

  st <- data.frame(sample_id = raw_metadata$sample_id, condition = condition,
                   stringsAsFactors = FALSE)
  for (cv in covariates) st[[cv]] <- factor(raw_metadata[[cv]])
  st$include <- !(st$sample_id %in% exclude_samples)

  used <- st[st$include, , drop = FALSE]
  used$condition <- droplevels(used$condition)
  warnings <- character()
  group_sizes <- table(used$condition)
  if (length(group_sizes) < 2) {
    stop("The condition needs at least two groups among the included samples.")
  }
  if (any(group_sizes < 2)) {
    warnings <- c(warnings, paste0(
      "Groups without replicates: ",
      paste(names(group_sizes)[group_sizes < 2], collapse = ", ")
    ))
  }
  # A design that cannot be fitted is an error: the sample table is not stored.
  design <- stats::as.formula(paste("~", paste(c(covariates, "condition"), collapse = " + ")))
  constant <- covariates[vapply(covariates, function(cv) length(unique(used[[cv]])) < 2, logical(1))]
  if (length(constant) > 0) {
    stop("Covariate(s) with only one value among the included samples: ",
         paste(constant, collapse = ", "), ". Remove them from covariates.")
  }
  mm <- stats::model.matrix(design, data = droplevels(used))
  if (qr(mm)$rank < ncol(mm)) {
    stop("The design ", paste(deparse(design), collapse = ""), " is not full rank: ",
         "a covariate is confounded with the condition or with another covariate. ",
         "Remove or change a covariate.")
  }

  list(
    objects = list(sample_table = st),
    table = st,
    summary = list(
      n_included = sum(st$include),
      n_excluded = sum(!st$include),
      condition_column = condition_column,
      reference_level = levels(used$condition)[1],
      group_sizes = as.list(group_sizes),
      covariates = covariates,
      design = paste(deparse(design), collapse = ""),
      warnings = warnings
    )
  )
}
