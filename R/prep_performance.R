# prep_performance.R
#
# prep_performance() converts performance package output objects into named
# lists for inline reporting. Supports:
#
#   model_performance() -> single-row data frame -> flat named list
#     e.g. perf_m1_$aic, perf_m1_$r2, perf_m1_$rmse
#
#   compare_performance() -> multi-row data frame -> nested list keyed by model name
#     e.g. comparison_$m_lm_full$aic, comparison_$m_lm_null$bic
#
# Column names are never hardcoded — all numeric columns are included as
# formatted values; the Name column (model name) is used as the row key for
# compare_performance.

#' Prepare a performance object for inline reporting
#'
#' Converts model_performance or compare_performance objects into a named list
#' suitable for inline R Markdown / Quarto reporting.
#'
#' @param obj A performance object (output of model_performance() or
#'   compare_performance()).
#'
#' @return For model_performance: a flat named list of formatted metric values.
#'   For compare_performance: a nested named list keyed by model name.
#'
#' @export
prep_performance <- function(obj) {
  df <- as.data.frame(obj)

  if (inherits(obj, "compare_performance")) {
    prep_compare_performance(df)
  } else {
    prep_model_performance(df)
  }
}

# Flattens a single-row model_performance data frame into a named list.
# All numeric columns are included; non-numeric columns are skipped.
prep_model_performance <- function(df) {
  result <- list()
  for (col in names(df)) {
    val <- df[[col]][1]
    if (is.numeric(val) && !is.na(val)) {
      result[[tolower(col)]] <- insight::format_value(val)
    }
  }
  result
}

# Converts a compare_performance data frame into a nested list keyed by the
# model name column. Non-name/class columns that are numeric become sub-values.
prep_compare_performance <- function(df) {
  name_col <- if ("Name" %in% names(df)) "Name" else names(df)[1]
  skip_cols <- c(name_col, "Model")
  value_cols <- setdiff(names(df), skip_cols)
  value_cols <- value_cols[vapply(df[value_cols], is.numeric, logical(1))]

  keys <- sanitize_key(as.character(df[[name_col]]))

  result <- stats::setNames(vector("list", nrow(df)), keys)
  for (i in seq_len(nrow(df))) {
    sub <- list()
    for (col in value_cols) {
      val <- df[[col]][i]
      if (!is.na(val)) {
        sub[[tolower(col)]] <- insight::format_value(val)
      }
    }
    result[[i]] <- sub
  }

  result
}
