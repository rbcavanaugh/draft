# class_modelbased.R
#
# Everything draft needs to handle modelbased objects - the output of
# estimate_means(), estimate_contrasts(), and estimate_slopes() from the
# modelbased package.
#
# Design principle: column names are never hardcoded. Label columns (row
# identifiers) are detected via the object's "by" attribute plus any
# character/factor columns. Value columns are everything else that is numeric.
#
# Row keys:
#   estimate_means     -> level value (e.g. "4", "6", "8")
#   estimate_contrasts -> "Level1_vs_Level2" (e.g. "6_vs_4")
#   estimate_slopes    -> level value if moderated, "result" if single row
#
# Exports: prep_modelbased()

# --- Prep ------------------------------------------------------------------

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
  df_rows_to_list(df, keys, value_cols)
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

# --- Render ----------------------------------------------------------------

render_modelbased_inspector <- function(data) {
  if (is.null(data$result)) {
    msg <- data$error_msg %||% "unknown error"
    return(inspector_error("Could not prepare this modelbased object.", msg))
  }

  mb_list   <- data$result
  list_name <- data$list_name
  obj_class <- data$obj_class

  section_title <- switch(obj_class,
    estimate_means          = "Marginal Means",
    estimate_contrasts      = "Contrasts",
    estimate_slopes         = "Marginal Effects",
    estimate_slopes_summary = "Marginal Effects",
    obj_class
  )

  rows <- lapply(names(mb_list), function(key) {
    param <- mb_list[[key]]
    base  <- paste0(list_name, "$", key, "$")

    chips <- lapply(names(param), function(col) {
      value_chip(col, param[[col]], paste0(base, col))
    })

    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        param_name_label(key, key)
      ),
      shiny::div(class = "param-values", chips)
    )
  })

  shiny::div(class = "inspector-split",
    shiny::div(class = "inspector-top",
      refer_as_bar(list_name),
      shiny::div(class = "inspector-section-title", section_title),
      do.call(shiny::div, c(list(class = "param-list"), rows))
    ),
    shiny::div(class = "inspector-bottom",
      shiny::div(class = "inspector-section-title", "Preview"),
      render_modelbased_table(mb_list)
    )
  )
}

render_modelbased_table <- function(lst) render_keyed_list_table(lst)

# --- Handler registration --------------------------------------------------

register_handler(
  type        = "modelbased",
  priority    = 20L,
  badge       = "MB",
  detect      = function(obj) inherits(obj, c("estimate_means", "estimate_contrasts", "estimate_slopes")),
  class_label = function(obj) class(obj)[1],
  size_label  = function(obj) paste0(nrow(obj), " rows"),
  prep        = function(obj, context) prep_modelbased(obj),
  setup_code  = function(nm, ln) sprintf("%s <- draft::prep_modelbased(%s)", ln, nm),
  render      = render_modelbased_inspector
)
