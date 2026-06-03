# prep_data.R
#
# prep_data() is the exported function for preparing a data frame for inline
# reporting. It returns a nested named list keyed by sanitized column names.
# Column type determines the structure of each element:
#
#   Continuous (numeric/integer with many unique values):
#     list(mean, sd, median, min, max, n, n_missing)
#
#   Categorical (factor, character, logical, or integer with few unique values):
#     list(
#       n        = total non-missing,
#       n_missing = count of NAs,
#       <level>  = list(n, pct)   -- one entry per level
#     )
#
# All values are formatted strings (via insight::format_value) so they are
# ready to drop directly into inline reporting text.
#
# raw_columns() is an internal helper used by the UI inspector panel. It returns
# a simple data frame describing each column's name, type label, and access path
# for the "raw" mode display (no summary transformation).

#' Prepare a data frame for inline reporting
#'
#' Computes summary statistics for each column and returns a nested named list
#' suitable for inline R Markdown / Quarto reporting.
#'
#' @param df A data frame or tibble.
#' @param cat_threshold Integer. Numeric/integer columns with this many or fewer
#'   unique non-missing values are treated as categorical. Default 10.
#'
#' @return A named list with one element per column, each containing formatted
#'   summary statistics ready for inline use.
#'
#' @export
prep_data <- function(df, cat_threshold = 10) {
  if (!is.data.frame(df)) stop("`df` must be a data frame.", call. = FALSE)

  cols <- names(df)
  keys <- sanitize_key(cols)

  result <- stats::setNames(
    lapply(seq_along(cols), function(i) {
      summarise_column(df[[cols[i]]], cat_threshold)
    }),
    keys
  )

  result
}

# Dispatches a single column to the appropriate summary function based on type.
summarise_column <- function(x, cat_threshold) {
  if (is_categorical(x, cat_threshold)) {
    summarise_categorical(x)
  } else {
    summarise_continuous(x)
  }
}

# A column is treated as categorical if it is a factor, character, logical,
# or a numeric/integer with <= cat_threshold unique non-missing values.
is_categorical <- function(x, cat_threshold) {
  if (is.factor(x) || is.character(x) || is.logical(x)) return(TRUE)
  if (is.numeric(x) || is.integer(x)) {
    return(length(unique(stats::na.omit(x))) <= cat_threshold)
  }
  FALSE
}

# Summarises a continuous column. All values returned as formatted strings.
# Guards against empty or all-NA columns, which produce NaN/Inf from base
# aggregation functions  --  returns "NA" strings rather than crashing.
summarise_continuous <- function(x) {
  vals <- stats::na.omit(x)

  if (length(vals) == 0) {
    return(list(
      mean = "NA", sd = "NA", median = "NA",
      min = "NA", max = "NA",
      n = "0", n_missing = as.character(sum(is.na(x)))
    ))
  }

  list(
    mean      = insight::format_value(mean(vals)),
    sd        = if (length(vals) > 1) insight::format_value(stats::sd(vals)) else "NA",
    median    = insight::format_value(stats::median(vals)),
    min       = insight::format_value(min(vals)),
    max       = insight::format_value(max(vals)),
    n         = as.character(length(vals)),
    n_missing = as.character(sum(is.na(x)))
  )
}

# Summarises a categorical column. Produces per-level n and pct sub-lists,
# plus overall n and n_missing. Level names are sanitized for safe list access.
summarise_categorical <- function(x) {
  # Filter NAs before converting to character so that NA values in logical or
  # other vectors are not stringified to "NA" and then counted as a level.
  non_miss  <- as.character(x[!is.na(x)])
  n_total   <- length(non_miss)
  n_missing <- sum(is.na(x))

  level_counts <- table(non_miss, deparse.level = 0)
  level_names  <- names(level_counts)
  level_keys   <- level_names

  levels_list <- stats::setNames(
    lapply(seq_along(level_names), function(i) {
      n   <- as.integer(level_counts[level_names[i]])
      pct <- if (n_total > 0) round(n / n_total * 100, 1) else NA_real_
      list(
        n   = as.character(n),
        pct = as.character(pct)
      )
    }),
    level_keys
  )

  c(
    list(n = as.character(n_total), n_missing = as.character(n_missing)),
    levels_list
  )
}

# Returns a data frame describing each column for the UI inspector's raw mode.
# Columns: key (sanitized), name (original), type_label, path (e.g. df$age).
raw_columns <- function(df, df_name = "df") {
  cols <- names(df)
  data.frame(
    key        = sanitize_key(cols),
    name       = cols,
    type_label = vapply(df, column_type_label, character(1)),
    path       = paste0(df_name, "$", cols),
    stringsAsFactors = FALSE
  )
}

# Returns a short human-readable type label for a single column vector.
column_type_label <- function(x) {
  if (is.factor(x))    return("factor")
  if (is.character(x)) return("character")
  if (is.logical(x))   return("logical")
  if (is.integer(x))   return("integer")
  if (is.numeric(x))   return("numeric")
  class(x)[1]
}
