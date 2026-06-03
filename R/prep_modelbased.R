# prep_modelbased.R
#
# prep_modelbased() converts modelbased output objects into nested named lists
# for inline reporting. Supports estimate_means, estimate_contrasts, and
# estimate_slopes objects from the modelbased package.
#
# Design principle: column names are never hardcoded. Label columns (row
# identifiers) are detected via the object's "by" attribute plus any
# character/factor columns. Value columns are everything else that is numeric.
#
# Row keys are built from label column values:
#   estimate_means      -> level value (e.g. "4", "6", "8")
#   estimate_contrasts  -> "Level1_vs_Level2" (e.g. "6_vs_4")
#   estimate_slopes     -> level value if moderated, "result" if single row

#' Prepare a modelbased object for inline reporting
#'
#' Converts estimate_means, estimate_contrasts, or estimate_slopes objects into
#' a nested named list suitable for inline R Markdown / Quarto reporting.
#'
#' @param obj A modelbased object (estimate_means, estimate_contrasts, or
#'   estimate_slopes).
#'
#' @return A named list with one element per row. Each element is a named list
#'   of formatted values keyed by lowercased column name.
#'
#' @export
prep_modelbased <- function(obj) {
  df <- as.data.frame(obj)

  label_cols <- detect_label_cols(obj, df)
  value_cols <- setdiff(names(df), label_cols)
  value_cols <- value_cols[vapply(df[value_cols], is.numeric, logical(1))]

  keys <- build_row_keys(df, label_cols)

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

# Identifies which columns are row-identifier (label) columns vs value columns.
# Uses the object's "by" attribute for moderator variables (which may be numeric)
# and treats all character/factor columns as labels.
detect_label_cols <- function(obj, df) {
  by_vars   <- attr(obj, "by")
  char_cols <- names(df)[vapply(df, function(x) is.character(x) || is.factor(x), logical(1))]
  label_cols <- unique(c(char_cols, by_vars))
  intersect(label_cols, names(df))
}

# Builds sanitized row keys from label columns.
# Contrast objects get "X_vs_Y" keys; all others paste label values together.
build_row_keys <- function(df, label_cols) {
  if (length(label_cols) == 0) {
    return(if (nrow(df) == 1) "result" else paste0("row_", seq_len(nrow(df))))
  }

  if ("Level1" %in% label_cols && "Level2" %in% label_cols) {
    keys <- paste0(df$Level1, "_vs_", df$Level2)
    return(sanitize_key(keys))
  }

  if (length(label_cols) == 1) {
    keys <- as.character(df[[label_cols]])
  } else {
    keys <- apply(df[label_cols], 1, function(row) paste(row, collapse = "_"))
  }

  sanitize_key(keys)
}
