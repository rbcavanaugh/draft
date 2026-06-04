# class_datawizard.R
#
# Everything draft needs to handle datawizard distribution summary objects —
# the output of describe_distribution() from the datawizard package.
#
# Two shapes depending on whether a `by` argument was used:
#
#   No stratification:
#     describe_distribution(iris) -> keyed by Variable
#     e.g. dist_$sepal_length$mean, dist_$sepal_length$sd
#
#   Stratified (by = "Species"):
#     describe_distribution(iris, by = "Species") -> keyed by group then Variable
#     e.g. dist_$setosa$sepal_length$mean, dist_$versicolor$sepal_length$sd
#
# The `Variable` column is always present. Any columns that appear before it
# are the grouping variables from the `by` argument.
#
# Column names are never hardcoded — all numeric columns after `Variable`
# become fields automatically.
#
# Exports: prep_distribution()

# --- Prep ------------------------------------------------------------------

#' Prepare a describe_distribution object for inline reporting
#'
#' Converts a parameters_distribution object (output of
#' datawizard::describe_distribution()) into a nested named list suitable for
#' inline R Markdown / Quarto reporting.
#'
#' @param obj A parameters_distribution object.
#'
#' @return Without stratification: a named list keyed by variable name, each
#'   element containing formatted summary statistics. With stratification: a
#'   nested named list keyed first by group then by variable name.
#'
#' @export
prep_distribution <- function(obj) {
  if (!inherits(obj, "parameters_distribution")) {
    stop("prep_distribution requires a parameters_distribution object (from datawizard::describe_distribution()).")
  }

  df <- as.data.frame(obj)

  # Columns before "Variable" are grouping variables (from `by` argument).
  var_col_idx <- which(names(df) == "Variable")
  by_cols     <- names(df)[seq_len(var_col_idx - 1)]

  # Value columns: everything after "Variable" that is numeric
  all_after   <- names(df)[(var_col_idx + 1):ncol(df)]
  value_cols  <- all_after[vapply(df[all_after], is.numeric, logical(1))]

  if (length(by_cols) == 0) {
    prep_distribution_flat(df, value_cols)
  } else {
    prep_distribution_stratified(df, by_cols, value_cols)
  }
}

# No stratification: one entry per Variable row
prep_distribution_flat <- function(df, value_cols) {
  keys <- sanitize_key(as.character(df$Variable))
  df_rows_to_list(df, keys, value_cols)
}

# Stratified: one top-level entry per group, each containing a flat sub-list
prep_distribution_stratified <- function(df, by_cols, value_cols) {
  if (length(by_cols) == 1) {
    raw_groups <- as.character(df[[by_cols]])
  } else {
    raw_groups <- apply(df[by_cols], 1, function(r) paste(r, collapse = "_"))
  }

  unique_raw  <- unique(raw_groups)
  group_keys  <- sanitize_key(unique_raw)
  result      <- stats::setNames(vector("list", length(unique_raw)), group_keys)

  for (i in seq_along(unique_raw)) {
    rows       <- df[raw_groups == unique_raw[i], ]
    result[[i]] <- prep_distribution_flat(rows, value_cols)
  }

  result
}

# --- Render ----------------------------------------------------------------

render_distribution_inspector <- function(data) {
  if (is.null(data$result)) {
    msg <- data$error_msg %||% "unknown error"
    return(inspector_error("Could not prepare this distribution object.", msg))
  }

  dist_list <- data$result
  list_name <- data$list_name

  # Detect whether result is stratified (values are sub-lists, not character)
  is_stratified <- length(dist_list) > 0 && is.list(dist_list[[1]]) &&
                   length(dist_list[[1]]) > 0 && is.list(dist_list[[1]][[1]])

  if (is_stratified) {
    rows <- lapply(names(dist_list), function(grp) {
      grp_list <- dist_list[[grp]]

      var_rows <- lapply(names(grp_list), function(var_key) {
        param <- grp_list[[var_key]]
        base  <- paste0(list_name, "$", grp, "$", var_key, "$")

        chips <- lapply(names(param), function(col) {
          value_chip(col, param[[col]], paste0(base, col))
        })

        shiny::div(class = "param-row",
          shiny::div(class = "param-names",
            param_name_label(var_key, var_key)
          ),
          shiny::div(class = "param-values", chips)
        )
      })

      shiny::tagList(
        shiny::div(class = "inspector-section-title", grp),
        do.call(shiny::div, c(list(class = "param-list"), var_rows))
      )
    })

    shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        refer_as_bar(list_name),
        rows
      ),
      shiny::div(class = "inspector-bottom",
        shiny::div(class = "inspector-section-title", "Preview"),
        render_distribution_table(dist_list, stratified = TRUE)
      )
    )

  } else {
    rows <- lapply(names(dist_list), function(var_key) {
      param <- dist_list[[var_key]]
      base  <- paste0(list_name, "$", var_key, "$")

      chips <- lapply(names(param), function(col) {
        value_chip(col, param[[col]], paste0(base, col))
      })

      shiny::div(class = "param-row",
        shiny::div(class = "param-names",
          shiny::span(class = "param-key", var_key)
        ),
        shiny::div(class = "param-values", chips)
      )
    })

    shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        refer_as_bar(list_name),
        shiny::div(class = "inspector-section-title", "Distribution Summary"),
        do.call(shiny::div, c(list(class = "param-list"), rows))
      ),
      shiny::div(class = "inspector-bottom",
        shiny::div(class = "inspector-section-title", "Preview"),
        render_distribution_table(dist_list, stratified = FALSE)
      )
    )
  }
}

render_distribution_table <- function(dist_list, stratified = FALSE) {
  if (length(dist_list) == 0) return(shiny::div())

  if (stratified) {
    # Flatten: group / variable / val_col columns
    first_grp  <- dist_list[[1]]
    if (length(first_grp) == 0) return(shiny::div())
    val_cols   <- names(first_grp[[1]])
    headers    <- c("Group", "Variable", val_cols)

    body_rows <- unlist(lapply(names(dist_list), function(grp) {
      lapply(names(dist_list[[grp]]), function(var_key) {
        el    <- dist_list[[grp]][[var_key]]
        cells <- lapply(val_cols, function(col) shiny::tags$td(el[[col]] %||% ""))
        shiny::tags$tr(c(
          list(shiny::tags$td(class = "tbl-key", grp),
               shiny::tags$td(class = "tbl-key", var_key)),
          cells
        ))
      })
    }), recursive = FALSE)

    preview_table(headers, body_rows)

  } else {
    val_cols  <- names(dist_list[[1]])
    headers   <- c("Variable", val_cols)

    body_rows <- lapply(names(dist_list), function(var_key) {
      el    <- dist_list[[var_key]]
      cells <- lapply(val_cols, function(col) shiny::tags$td(el[[col]] %||% ""))
      shiny::tags$tr(c(list(shiny::tags$td(class = "tbl-key", var_key)), cells))
    })

    preview_table(headers, body_rows)
  }
}

# --- Handler registration --------------------------------------------------

register_handler(
  type        = "datawizard",
  priority    = 25L,
  badge       = "DW",
  detect      = function(obj) inherits(obj, "parameters_distribution"),
  class_label = function(obj) "distribution summary",
  size_label  = function(obj) {
    df  <- as.data.frame(obj)
    n   <- length(unique(df$Variable))
    by  <- setdiff(names(df)[seq_len(which(names(df) == "Variable") - 1)], character(0))
    if (length(by) > 0) {
      paste0(n, " vars × ", length(unique(df[[by[1]]])), " groups")
    } else {
      paste0(n, " variables")
    }
  },
  prep        = function(obj, context) prep_distribution(obj),
  setup_code  = function(nm, ln) sprintf("%s <- draft::prep_distribution(%s)", ln, nm),
  render      = render_distribution_inspector
)
