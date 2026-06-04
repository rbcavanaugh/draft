# class_effectsize.R
#
# Everything draft needs to handle effectsize package output objects.
# Supports any object inheriting from effectsize_table, which covers:
#
#   effectsize_difference  e.g. cohens_d(), hedges_g(), glass_delta()
#   effectsize_anova       e.g. eta_squared(), omega_squared(), epsilon_squared()
#   effectsize_table       e.g. cramers_v(), cohens_w(), phi()
#
# Design principle: column names are never hardcoded. If a "Parameter" column
# is present the result is keyed by it (one entry per effect); otherwise it is
# a single-row object and a flat named list is returned, matching the
# prep_performance pattern for single models.
#
# Exports: prep_effectsize()

# --- Prep ------------------------------------------------------------------

#' Prepare an effectsize object for inline reporting
#'
#' Converts any effectsize_table object into a named list suitable for inline
#' R Markdown / Quarto reporting. Multi-row objects (e.g. eta_squared with
#' multiple predictors) are keyed by the Parameter column. Single-row objects
#' (e.g. cohens_d) are returned as a flat named list.
#'
#' @param obj An effectsize object inheriting from effectsize_table.
#'
#' @return A named list of formatted character values (single-row objects) or a
#'   nested named list keyed by parameter name (multi-row objects).
#'
#' @export
prep_effectsize <- function(obj) {
  if (!inherits(obj, "effectsize_table")) {
    stop("prep_effectsize requires an effectsize_table object.")
  }

  df <- as.data.frame(obj)

  if ("Parameter" %in% names(df) && nrow(df) > 1) {
    prep_effectsize_multi(df)
  } else {
    prep_effectsize_flat(df)
  }
}

# Columns that are structural metadata rather than reportable values
.es_skip_cols <- c("Parameter", "CI")

# Multi-row: one entry per Parameter level (e.g. eta_squared with 2+ predictors)
prep_effectsize_multi <- function(df) {
  value_cols <- setdiff(names(df), .es_skip_cols)
  value_cols <- value_cols[vapply(df[value_cols], is.numeric, logical(1))]

  keys <- sanitize_key(as.character(df$Parameter))
  df_rows_to_list(df, keys, value_cols)
}

# Single-row (or single-parameter): flat named list of field = value
prep_effectsize_flat <- function(df) {
  value_cols <- setdiff(names(df), .es_skip_cols)
  value_cols <- value_cols[vapply(df[value_cols], is.numeric, logical(1))]

  result <- list()
  for (col in value_cols) {
    val <- df[[col]][1]
    if (!is.na(val)) {
      result[[tolower(col)]] <- format_col(val, col)
    }
  }

  result
}

# --- Render ----------------------------------------------------------------

render_effectsize_inspector <- function(data) {
  if (is.null(data$result)) {
    msg <- data$error_msg %||% "unknown error"
    return(inspector_error("Could not prepare this effectsize object.", msg))
  }

  es_list   <- data$result
  list_name <- data$list_name

  # Detect whether result is flat (single-row) or nested (multi-row)
  is_flat <- length(es_list) > 0 && !is.list(es_list[[1]])

  if (is_flat) {
    base  <- paste0(list_name, "$")
    chips <- lapply(names(es_list), function(col) {
      value_chip(col, es_list[[col]], paste0(base, col))
    })

    shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        refer_as_bar(list_name),
        shiny::div(class = "inspector-section-title", "Effect Size"),
        shiny::div(class = "param-list",
          shiny::div(class = "param-row",
            shiny::div(class = "param-names",
              param_name_label(data$obj_class, data$obj_class)
            ),
            shiny::div(class = "param-values", chips)
          )
        )
      ),
      shiny::div(class = "inspector-bottom")
    )

  } else {
    rows <- lapply(names(es_list), function(key) {
      param <- es_list[[key]]
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
        shiny::div(class = "inspector-section-title", "Effect Sizes"),
        do.call(shiny::div, c(list(class = "param-list"), rows))
      ),
      shiny::div(class = "inspector-bottom",
        shiny::div(class = "inspector-section-title", "Preview"),
        render_effectsize_table(es_list)
      )
    )
  }
}

render_effectsize_table <- function(lst) render_keyed_list_table(lst)

# --- Handler registration --------------------------------------------------

register_handler(
  type        = "effectsize",
  priority    = 15L,
  badge       = "ES",
  detect      = function(obj) inherits(obj, "effectsize_table"),
  class_label = function(obj) class(obj)[1],
  size_label  = function(obj) {
    n <- nrow(as.data.frame(obj))
    if (n == 1) "1 effect" else paste0(n, " effects")
  },
  prep        = function(obj, context) prep_effectsize(obj),
  setup_code  = function(nm, ln) sprintf("%s <- draft::prep_effectsize(%s)", ln, nm),
  render      = render_effectsize_inspector
)
