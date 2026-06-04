# class_dataframe.R
#
# Everything draft needs to handle plain data frames and tibbles.
# Two modes: summary (computed statistics per column) and raw (direct $col access).
#
# Shared render helpers (render_data_list_chips, render_data_list_table) are
# in render_inspector_panel.R; they are also used by the generic list inspector.
#
# Exports: prep_data()

# --- Prep ------------------------------------------------------------------

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

  # Skip factor/character columns with more unique values than cat_threshold —
  # they are ID-like columns with no useful summary to copy inline.
  keep <- vapply(cols, function(col) {
    x <- df[[col]]
    if ((is.factor(x) || is.character(x)) && !is.logical(x)) {
      length(unique(stats::na.omit(x))) <= cat_threshold
    } else {
      TRUE
    }
  }, logical(1))

  cols <- cols[keep]
  keys <- sanitize_key(cols)

  stats::setNames(
    lapply(seq_along(cols), function(i) summarise_column(df[[cols[i]]], cat_threshold)),
    keys
  )
}

# Returns the original column names that pass the cat_threshold filter —
# i.e., the names whose summaries appear in prep_data() output.
kept_col_names <- function(df, cat_threshold = 10) {
  cols <- names(df)
  keep <- vapply(cols, function(col) {
    x <- df[[col]]
    if ((is.factor(x) || is.character(x)) && !is.logical(x)) {
      length(unique(stats::na.omit(x))) <= cat_threshold
    } else {
      TRUE
    }
  }, logical(1))
  cols[keep]
}

summarise_column <- function(x, cat_threshold) {
  if (is_categorical(x, cat_threshold)) summarise_categorical(x) else summarise_continuous(x)
}

is_categorical <- function(x, cat_threshold) {
  if (is.factor(x) || is.character(x) || is.logical(x)) return(TRUE)
  if (is.numeric(x) || is.integer(x)) return(length(unique(stats::na.omit(x))) <= cat_threshold)
  FALSE
}

summarise_continuous <- function(x) {
  vals <- stats::na.omit(x)
  if (length(vals) == 0) {
    return(list(mean = "NA", sd = "NA", median = "NA",
                min = "NA", max = "NA", n = "0",
                n_missing = as.character(sum(is.na(x)))))
  }
  list(
    mean      = insight::format_value(mean(vals),           zap_small = TRUE, protect_integers = TRUE),
    sd        = if (length(vals) > 1) insight::format_value(stats::sd(vals),     zap_small = TRUE, protect_integers = TRUE) else "NA",
    median    = insight::format_value(stats::median(vals),  zap_small = TRUE, protect_integers = TRUE),
    min       = insight::format_value(min(vals),            zap_small = TRUE, protect_integers = TRUE),
    max       = insight::format_value(max(vals),            zap_small = TRUE, protect_integers = TRUE),
    n         = as.character(length(vals)),
    n_missing = as.character(sum(is.na(x)))
  )
}

summarise_categorical <- function(x) {
  non_miss     <- as.character(x[!is.na(x)])
  n_total      <- length(non_miss)
  n_missing    <- sum(is.na(x))
  level_counts <- table(non_miss, deparse.level = 0)
  level_names  <- names(level_counts)

  levels_list <- stats::setNames(
    lapply(seq_along(level_names), function(i) {
      n   <- as.integer(level_counts[level_names[i]])
      pct <- if (n_total > 0) round(n / n_total * 100, 1) else NA_real_
      list(n = as.character(n), pct = as.character(pct))
    }),
    level_names
  )

  c(list(n = as.character(n_total), n_missing = as.character(n_missing)), levels_list)
}

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

column_type_label <- function(x) {
  if (is.factor(x))    return("factor")
  if (is.character(x)) return("character")
  if (is.logical(x))   return("logical")
  if (is.integer(x))   return("integer")
  if (is.numeric(x))   return("numeric")
  class(x)[1]
}

# --- Render ----------------------------------------------------------------

render_dataframe_inspector <- function(data) {
  list_name <- data$list_name
  result    <- data$result

  if (result$mode == "raw") {
    return(shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        refer_as_bar(list_name),
        render_raw_columns_table(result$raw)
      ),
      shiny::div(class = "inspector-bottom")
    ))
  }

  if (is.null(result$summary)) {
    msg <- result$summary_err %||% "unknown error"
    return(inspector_error("Could not summarise this data frame.", msg))
  }

  col_names <- result$kept_cols %||% names(result$obj)
  keys      <- names(result$summary)
  col_nms   <- vapply(seq_along(keys), function(i)
                 if (i <= length(col_names)) col_names[i] else keys[i], character(1))
  show_orig <- any_original_differs(col_nms, keys)

  rows <- lapply(seq_along(keys), function(i) {
    key    <- keys[i]
    col_nm <- col_nms[i]
    base   <- paste0(list_name, "$", key, "$")

    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        param_name_label(col_nm, key, show_orig)
      ),
      shiny::div(class = "param-values",
        render_summary_chips(result$summary[[key]], base)
      )
    )
  })

  shiny::div(class = "inspector-split",
    shiny::div(class = "inspector-top",
      refer_as_bar(list_name),
      shiny::div(class = "inspector-section-title", "Inline reference paths"),
      shiny::div(class = "param-list", rows)
    ),
    shiny::div(class = "inspector-bottom",
      shiny::div(class = "inspector-section-title", "Data summary"),
      render_data_list_table(result$summary)
    )
  )
}

render_summary_chips <- function(summary, base) {
  if ("mean" %in% names(summary)) {
    shiny::tagList(
      value_chip("mean",   summary$mean,   paste0(base, "mean")),
      value_chip("sd",     summary$sd,     paste0(base, "sd")),
      value_chip("median", summary$median, paste0(base, "median")),
      value_chip("n",      summary$n,      paste0(base, "n"))
    )
  } else {
    level_keys  <- setdiff(names(summary), c("n", "n_missing"))
    shown_keys  <- level_keys[seq_len(min(5, length(level_keys)))]
    level_chips <- lapply(shown_keys, function(lk) {
      value_chip(paste0(lk, " %"), paste0(summary[[lk]]$pct, "%"), paste0(base, lk, "$pct"))
    })
    overflow <- if (length(level_keys) > 5)
      list(shiny::span(class = "chip-muted", paste0("+ ", length(level_keys) - 5, " more levels")))
    else list()

    shiny::tagList(
      value_chip("n", summary$n, paste0(base, "n")),
      unname(level_chips),
      overflow
    )
  }
}

render_raw_columns_table <- function(raw_df) {
  rows <- lapply(seq_len(nrow(raw_df)), function(i) {
    row <- raw_df[i, ]
    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        param_name_label(row$name, row$name),
        shiny::span(class = "chip-muted", row$type_label)
      ),
      shiny::div(class = "param-values", value_chip("path", row$path, row$path))
    )
  })
  shiny::tagList(
    shiny::div(class = "inspector-section-title", "Columns (raw access)"),
    shiny::div(class = "param-list", rows)
  )
}

# --- Handler registration --------------------------------------------------
# render_data_list_chips and render_data_list_table are shared helpers
# defined in render_inspector_panel.R and used by both this renderer and
# the generic list inspector.

register_handler(
  type        = "dataframe",
  priority    = 50L,
  badge       = "D",
  detect      = function(obj) is.data.frame(obj),
  class_label = function(obj) if (inherits(obj, "tbl")) "tibble" else "data.frame",
  size_label  = function(obj) paste0(nrow(obj), " x ", ncol(obj)),
  context     = function(input) list(mode = input$df_mode %||% "summary"),
  prep        = function(obj, context) {
    mode <- context$mode %||% "summary"
    nm   <- context$nm   %||% "df"
    if (mode == "summary") {
      summary_err  <- NULL
      summary_list <- tryCatch(
        prep_data(obj),
        error = function(e) { summary_err <<- conditionMessage(e); NULL }
      )
      list(mode = "summary", summary = summary_list, obj = obj,
           kept_cols = kept_col_names(obj), summary_err = summary_err)
    } else {
      list(mode = "raw", raw = raw_columns(obj, nm))
    }
  },
  assign_result = function(result) result$summary,
  setup_code    = function(nm, ln) sprintf("%s <- draft::prep_data(%s)", ln, nm),
  controls      = function(nm, type) {
    shiny::div(class = "inspector-controls",
      shiny::radioButtons(
        inputId  = "df_mode",
        label    = NULL,
        choices  = c("Summary" = "summary", "Raw columns" = "raw"),
        selected = "summary",
        inline   = TRUE
      )
    )
  },
  render = render_dataframe_inspector
)
