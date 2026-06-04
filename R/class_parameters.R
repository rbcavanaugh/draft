# class_parameters.R
#
# Everything draft needs to handle parameters_model objects - the output of
# parameters::model_parameters(). Covers frequentist and Bayesian models;
# handles both standard and correlation parameter tables.
#
# Shared render helpers (render_model_list_chips, render_model_list_table) are
# in render_inspector_panel.R; they are also used by the generic list inspector.
#
# Exports: prep_params(), params_df_to_list()

# --- Prep ------------------------------------------------------------------

#' Prepare a parameters_model object for inline reporting
#'
#' Formats a `parameters_model` object (output of
#' `parameters::model_parameters()`) into a nested named list suitable for
#' inline R Markdown / Quarto reporting.
#'
#' @param params_obj A `parameters_model` object.
#'
#' @return A named list with one element per parameter. Each element is itself
#'   a named list of formatted strings for all available fields.
#'
#' @export
prep_params <- function(params_obj) {
  raw <- format(params_obj, zap_small = TRUE) |> dplyr::bind_rows()
  names(raw) <- tolower(names(raw))
  names(raw) <- gsub("\\s+", "_", names(raw))
  names(raw) <- gsub("[^a-z0-9_]", "", names(raw))

  if ("parameter" %in% names(raw)) {
    raw$key <- sanitize_key(raw$parameter)
  } else if ("parameter1" %in% names(raw) && "parameter2" %in% names(raw)) {
    raw$key <- sanitize_key(paste(raw$parameter1, raw$parameter2, sep = "_"))
  } else {
    stop("Could not find parameter column(s) to create keys")
  }

  params_df_to_list(raw)
}

#' Convert a formatted parameters data frame to a nested list
#'
#' @param params A data frame with a `key` column and formatted value columns.
#'
#' @return A named list with one element per row, keyed by `key`.
#'
#' @export
#' @keywords internal
params_df_to_list <- function(params) {
  result <- vector("list", nrow(params))
  names(result) <- params$key

  for (i in seq_len(nrow(params))) {
    row <- params[i, ]
    sub <- list()
    for (col in names(row)) {
      if (col != "key" && is_present(row[[col]])) {
        sub[[col]] <- row[[col]]
      }
    }
    result[[i]] <- sub
  }

  result
}

is_present <- function(x) !is.na(x) && nzchar(as.character(x))

# --- Render ----------------------------------------------------------------

render_model_inspector <- function(data) {
  if (is.null(data$result)) {
    msg <- data$error_msg %||% "unknown error"
    return(inspector_error("Could not extract parameters from this model.", msg))
  }

  params_list <- data$result
  list_name   <- data$list_name

  # Derive original display name for each key upfront so we can decide once
  # whether any row differs before rendering.
  get_original <- function(param) {
    if (!is.null(param$parameter)) {
      param$parameter
    } else if (!is.null(param$parameter1) && !is.null(param$parameter2)) {
      paste0(param$parameter1, " x ", param$parameter2)
    } else {
      NULL
    }
  }

  keys      <- names(params_list)
  originals <- lapply(params_list, get_original)
  show_orig <- any_original_differs(originals, keys)

  rows <- lapply(keys, function(key) {
    param  <- params_list[[key]]
    base   <- paste0(list_name, "$", key, "$")

    chips <- Filter(Negate(is.null), lapply(names(param), function(col) {
      val <- param[[col]]
      if (is.null(val) || is.na(val) || !nzchar(as.character(val))) return(NULL)
      if (col %in% c("parameter1", "parameter2")) return(NULL)
      path <- if (grepl("^[0-9]", col)) {
        paste0(list_name, "$", key, '[[\"', col, '\"]]')
      } else {
        paste0(base, col)
      }
      value_chip(col, val, path)
    }))

    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        param_name_label(get_original(param), key, show_orig)
      ),
      shiny::div(class = "param-values", chips)
    )
  })

  shiny::div(class = "inspector-split",
    shiny::div(class = "inspector-top",
      refer_as_bar(list_name),
      shiny::div(class = "inspector-section-title", "Inline reference paths"),
      do.call(shiny::div, c(list(class = "param-list"), rows))
    ),
    shiny::div(class = "inspector-bottom",
      shiny::div(class = "inspector-section-title", "Model parameters"),
      render_model_list_table(params_list)
    )
  )
}

# --- Handler registration --------------------------------------------------
# render_model_list_chips and render_model_list_table are shared helpers
# defined in render_inspector_panel.R and used by both this renderer and
# the generic list inspector.

register_handler(
  type        = "parameters_model",
  priority    = 10L,
  badge       = "P",
  detect      = function(obj) inherits(obj, "parameters_model"),
  class_label = function(obj) "parameters",
  size_label  = function(obj) paste0(nrow(obj), " parameters"),
  prep        = function(obj, context) prep_params(obj),
  setup_code  = function(nm, ln) sprintf("%s <- draft::prep_params(%s)", ln, nm),
  render      = render_model_inspector
)
