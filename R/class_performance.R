# class_performance.R
#
# Everything draft needs to handle performance package output objects.
# Supports:
#
#   model_performance() -> single-row data frame -> flat named list
#     e.g. perf_m1_$aic, perf_m1_$r2, perf_m1_$rmse
#
#   compare_performance() -> multi-row data frame -> nested list keyed by model name
#     e.g. comparison_$m_lm_full$aic, comparison_$m_lm_null$bic
#
# Column names are never hardcoded - all numeric columns are included as
# formatted values; the Name column (model name) is used as the row key for
# compare_performance.
#
# Exports: prep_performance()

# --- Prep ------------------------------------------------------------------

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
prep_model_performance <- function(df) {
  result <- list()
  for (col in names(df)) {
    val <- df[[col]][1]
    if (is.numeric(val) && !is.na(val)) {
      result[[tolower(col)]] <- format_col(val, col)
    }
  }
  result
}

# Converts a compare_performance data frame into a nested list keyed by
# model name. Non-name/class columns that are numeric become sub-values.
prep_compare_performance <- function(df) {
  name_col   <- if ("Name" %in% names(df)) "Name" else names(df)[1]
  skip_cols  <- c(name_col, "Model")
  value_cols <- setdiff(names(df), skip_cols)
  value_cols <- value_cols[vapply(df[value_cols], is.numeric, logical(1))]

  keys <- sanitize_key(as.character(df[[name_col]]))
  df_rows_to_list(df, keys, value_cols)
}

# --- Render ----------------------------------------------------------------

render_performance_inspector <- function(data) {
  if (is.null(data$result)) {
    msg <- data$error_msg %||% "unknown error"
    return(inspector_error("Could not prepare this performance object.", msg))
  }

  perf_list <- data$result
  list_name <- data$list_name
  obj_class <- data$obj_class

  if (obj_class == "compare_performance") {
    rows <- lapply(names(perf_list), function(model_key) {
      metrics <- perf_list[[model_key]]
      base    <- paste0(list_name, "$", model_key, "$")

      chips <- lapply(names(metrics), function(col) {
        value_chip(col, metrics[[col]], paste0(base, col))
      })

      shiny::div(class = "param-row",
        shiny::div(class = "param-names",
          param_name_label(model_key, model_key)
        ),
        shiny::div(class = "param-values", chips)
      )
    })

    shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        refer_as_bar(list_name),
        shiny::div(class = "inspector-section-title", "Model Comparison"),
        do.call(shiny::div, c(list(class = "param-list"), rows))
      ),
      shiny::div(class = "inspector-bottom",
        shiny::div(class = "inspector-section-title", "Preview"),
        render_performance_table(perf_list)
      )
    )

  } else {
    # Single model - flat list, all chips in one row
    base  <- paste0(list_name, "$")
    chips <- lapply(names(perf_list), function(col) {
      value_chip(col, perf_list[[col]], paste0(base, col))
    })

    shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        refer_as_bar(list_name),
        shiny::div(class = "inspector-section-title", "Model Performance"),
        shiny::div(class = "param-list",
          shiny::div(class = "param-row",
            shiny::div(class = "param-names",
              param_name_label("metrics", "metrics")
            ),
            shiny::div(class = "param-values", chips)
          )
        )
      ),
      shiny::div(class = "inspector-bottom")
    )
  }
}

render_performance_table <- function(lst) render_keyed_list_table(lst)

# --- Handler registration --------------------------------------------------

register_handler(
  type        = "performance",
  priority    = 30L,
  badge       = "PF",
  detect      = function(obj) inherits(obj, c("performance_model", "compare_performance")),
  class_label = function(obj) class(obj)[1],
  size_label  = function(obj) {
    if (inherits(obj, "compare_performance")) paste0(nrow(obj), " models") else "1 model"
  },
  prep        = function(obj, context) prep_performance(obj),
  setup_code  = function(nm, ln) sprintf("%s <- draft::prep_performance(%s)", ln, nm),
  render      = render_performance_inspector
)
