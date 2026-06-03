# render_inspector_panel.R
#
# Builds Panel 2 (Object Inspector) UI. Receives a pre-computed `data` list
# from the server's inspector_data() reactive rather than computing anything
# itself, keeping rendering and data logic separate.
#
# Dispatches to type-specific renderers:
#   model     -> render_model_inspector()
#   dataframe -> render_dataframe_inspector()
#   list      -> render_list_inspector()
#   other     -> render_unsupported()
#
# Each renderer produces:
#   (1) a parameter/stats table with inline-path chips for copy-pasting
#   (2) a copyable setup code block

# Controls row in the panel header (df mode toggle)
render_inspector_controls <- function(nm, type) {
  if (type == "dataframe") {
    shiny::div(class = "inspector-controls",
      shiny::radioButtons(
        inputId  = "df_mode",
        label    = NULL,
        choices  = c("Summary" = "summary", "Raw columns" = "raw"),
        selected = "summary",
        inline   = TRUE
      )
    )
  } else {
    NULL
  }
}

# Top-level dispatcher  --  receives the pre-computed data list from the server
render_inspector_content <- function(data) {
  switch(data$type,
    parameters_model = render_model_inspector(data),
    dataframe        = render_dataframe_inspector(data),
    modelbased       = render_modelbased_inspector(data),
    performance      = render_performance_inspector(data),
    list             = render_list_inspector(data),
    scalar           = render_scalar_inspector(data),
    render_unsupported()
  )
}

# --- Model inspector ---
#
# Top half: refer-as label + one chip row per parameter (estimate, CI, p/pd).
# Bottom half: clean parameter table for quick scanning.
# Setup code lives in Panel 3 (Copy setup chunk button), not here.
render_model_inspector <- function(data) {
  if (is.null(data$params_list)) {
    msg <- if (!is.null(data$error_msg)) data$error_msg else "unknown error"
    return(shiny::div(class = "inspector-error",
      shiny::strong("Could not extract parameters from this model."),
      shiny::br(),
      shiny::span(style = "font-size:11px; color:#888;", msg)
    ))
  }

  params_list <- data$params_list
  list_name   <- data$list_name

  rows <- lapply(names(params_list), function(key) {
    param <- params_list[[key]]
    fields <- build_field_paths(key, list_name)

    chips <- lapply(names(param), function(col) {
      val <- param[[col]]
      if (!is.null(val) && !is.na(val) && nzchar(as.character(val)) &&
          !col %in% c("parameter1", "parameter2")) {
        path <- if (grepl("^[0-9]", col)) {
          base_without_dollar <- sub("\\$$", "", fields$base)
          paste0(base_without_dollar, "[[\"", col, "\"]]")
        } else {
          paste0(fields$base, col)
        }
        value_chip(col, val, path)
      } else {
        NULL
      }
    })
    chips <- Filter(Negate(is.null), chips)

    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        shiny::span(class = "param-original", key),
        shiny::span(class = "param-key", key)
      ),
      shiny::div(class = "param-values", chips)
    )
  })

  shiny::div(class = "inspector-split",
    shiny::div(class = "inspector-top",
      shiny::div(class = "refer-as-bar",
        "Refer to this object as ",
        shiny::tags$code(paste0(list_name, "$..."))
      ),
      shiny::div(class = "inspector-section-title", "Inline reference paths"),
      do.call(shiny::div, c(list(class = "param-list"), rows))
    ),
    shiny::div(class = "inspector-bottom",
      shiny::div(class = "inspector-section-title", "Model parameters"),
      render_model_list_table(params_list)
    )
  )
}

# Renders a compact parameter table from params_df.
render_model_params_table <- function(df) {
  cols_to_show <- setdiff(names(df), c("parameter", "key"))

  body_rows <- lapply(seq_len(nrow(df)), function(i) {
    row <- df[i, ]
    cells <- lapply(cols_to_show, function(col) {
      val <- row[[col]]
      shiny::tags$td(if (!is.na(val) && nzchar(val)) val else "")
    })
    shiny::tags$tr(c(list(shiny::tags$td(class = "tbl-key", row$key)), cells))
  })

  headers <- c("Parameter", cols_to_show)

  shiny::div(class = "preview-table-wrap",
    shiny::tags$table(class = "preview-table",
      shiny::tags$thead(shiny::tags$tr(
        lapply(headers, shiny::tags$th)
      )),
      shiny::tags$tbody(body_rows)
    )
  )
}

# Builds a named list of full inline paths for a parameter key.
build_field_paths <- function(key, list_name) {
  base <- paste0(list_name, "$", key, "$")
  list(base = base)
}

# Renders a single value chip: label | formatted value | copy button.
# The copy button carries the full inline path as a data attribute; the
# clipboard JS in www/ handles the actual clipboard write on click.
value_chip <- function(label, value, path) {
  clipboard_text <- paste0("{", path, "}")
  shiny::div(class = "value-chip",
    shiny::span(class = "chip-label", label),
    shiny::span(class = "chip-value", value),
    shiny::tags$button(
      class             = "chip-copy",
      `data-clipboard`  = clipboard_text,
      title             = paste("Copy:", clipboard_text),
      shiny::icon("copy")
    )
  )
}

# --- Data frame inspector ---
#
# Summary mode: refer-as label + chip rows per column (top) + summary table (bottom).
# Raw mode: refer-as label + flat raw column list.
# Setup code lives in Panel 3 (Copy setup chunk button), not here.
render_dataframe_inspector <- function(data) {
  list_name <- data$list_name

  if (data$mode == "raw") {
    return(shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        shiny::div(class = "refer-as-bar",
          "Refer to this object as ",
          shiny::tags$code(paste0(list_name, "$..."))
        ),
        render_raw_columns_table(data$raw_df)
      ),
      shiny::div(class = "inspector-bottom")
    ))
  }

  if (is.null(data$summary_list)) {
    msg <- if (!is.null(data$summary_err)) data$summary_err else "unknown error"
    return(shiny::div(class = "inspector-error",
      shiny::strong("Could not summarise this data frame."),
      shiny::br(),
      shiny::span(style = "font-size:11px; color:#888;", msg)))
  }

  col_names <- names(data$obj)
  keys      <- names(data$summary_list)

  rows <- lapply(seq_along(keys), function(i) {
    key     <- keys[i]
    col_nm  <- if (i <= length(col_names)) col_names[i] else key
    summary <- data$summary_list[[key]]
    base    <- paste0(list_name, "$", key, "$")

    chips <- render_summary_chips(summary, base)

    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        shiny::span(class = "param-original", col_nm),
        shiny::span(class = "param-key",      key)
      ),
      shiny::div(class = "param-values", chips)
    )
  })

  table_result <- render_data_list_table(data$summary_list)

  result <- shiny::div(class = "inspector-split",
    shiny::div(class = "inspector-top",
      shiny::div(class = "refer-as-bar",
        "Refer to this object as ",
        shiny::tags$code(paste0(list_name, "$..."))
      ),
      shiny::div(class = "inspector-section-title", "Inline reference paths"),
      shiny::div(class = "param-list", rows)
    ),
    shiny::div(class = "inspector-bottom",
      shiny::div(class = "inspector-section-title", "Data summary"),
      table_result
    )
  )
  result
}

# Renders value chips for one summary element. Continuous columns get
# mean/SD/n chips; categorical columns get n and per-level pct chips
# (capped at 5 levels to avoid overwhelming the UI).
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
      pct_val <- summary[[lk]]$pct
      value_chip(
        paste0(lk, " %"),
        paste0(pct_val, "%"),
        paste0(base, lk, "$pct")
      )
    })
    overflow <- if (length(level_keys) > 5) {
      shiny::span(class = "chip-muted",
        paste0("+ ", length(level_keys) - 5, " more levels"))
    }
    result <- shiny::tagList(
      value_chip("n", summary$n, paste0(base, "n")),
      unname(level_chips),
      overflow
    )
    result
  }
}

render_raw_columns_table <- function(raw_df) {
  rows <- lapply(seq_len(nrow(raw_df)), function(i) {
    row <- raw_df[i, ]
    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        shiny::span(class = "param-original", row$name),
        shiny::span(class = "param-key chip-muted", row$type_label)
      ),
      shiny::div(class = "param-values",
        value_chip("path", row$path, row$path)
      )
    )
  })

  shiny::tagList(
    shiny::div(class = "inspector-section-title", "Columns (raw access)"),
    shiny::div(class = "param-list", rows)
  )
}

# --- List inspector ---
#
# Splits into two scrollable halves:
#   top    -- inline reference chips (copy-able paths for use in text)
#   bottom -- reconstructed table preview (model params or data summary)
render_list_inspector <- function(data) {
  obj       <- data$obj
  list_name <- data$list_name
  subtype   <- data$list_subtype %||% "generic_list"

  top_content <- switch(subtype,
    model_list = render_model_list_chips(obj, list_name),
    data_list  = render_data_list_chips(obj, list_name),
    render_generic_list_chips(obj, list_name)
  )

  bottom_content <- switch(subtype,
    model_list = render_model_list_table(obj),
    data_list  = render_data_list_table(obj),
    shiny::div(
      style = "color:#aaa; font-size:12px; font-style:italic; padding:4px;",
      paste0(length(obj), " elements - no structured preview available")
    )
  )

  shiny::div(class = "inspector-split",
    shiny::div(class = "inspector-top", top_content),
    shiny::div(class = "inspector-bottom",
      shiny::div(class = "inspector-section-title", "Data preview"),
      bottom_content
    )
  )
}

# Reference chips for a model-derived list (prep_model output).
# One row per parameter; chips for estimate, ci, p/pd.
render_model_list_chips <- function(obj, list_name) {
  keys <- names(obj)

  rows <- lapply(keys, function(key) {
    el   <- obj[[key]]
    base <- paste0(list_name, "$", key, "$")

    chips <- Filter(Negate(is.null), list(
      if (!is.null(el$estimate)) value_chip("estimate", el$estimate, paste0(base, "estimate")),
      if (!is.null(el$ci))       value_chip("ci",       el$ci,       paste0(base, "ci")),
      if (!is.null(el$p))        value_chip("p",        el$p,        paste0(base, "p")),
      if (!is.null(el$pd))       value_chip("pd",       el$pd,       paste0(base, "pd"))
    ))

    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        shiny::span(class = "param-key", key)
      ),
      shiny::div(class = "param-values", chips)
    )
  })

  shiny::tagList(
    shiny::div(class = "inspector-section-title", "Inline reference paths"),
    shiny::div(class = "param-list", rows)
  )
}

# Reference chips for a data-derived list (prep_data output).
# Continuous columns: mean/sd/median/n chips. Categorical: n + per-level pct chips.
render_data_list_chips <- function(obj, list_name) {
  keys <- names(obj)

  rows <- lapply(keys, function(key) {
    el   <- obj[[key]]
    base <- paste0(list_name, "$", key, "$")

    chips <- if (!is.null(el$mean)) {
      list(
        value_chip("mean",   el$mean,              paste0(base, "mean")),
        value_chip("sd",     el$sd     %||% "-", paste0(base, "sd")),
        value_chip("median", el$median %||% "-", paste0(base, "median")),
        value_chip("n",      el$n      %||% "-", paste0(base, "n"))
      )
    } else {
      level_keys  <- setdiff(names(el), c("n", "n_missing"))
      shown_keys  <- level_keys[seq_len(min(5, length(level_keys)))]
      level_chips <- lapply(shown_keys, function(lk) {
        value_chip(paste0(lk, " %"), paste0(el[[lk]]$pct, "%"), paste0(base, lk, "$pct"))
      })
      overflow <- if (length(level_keys) > 5)
        list(shiny::span(class = "chip-muted",
                         paste0("+ ", length(level_keys) - 5, " more")))
      else list()
      c(list(value_chip("n", el$n %||% "-", paste0(base, "n"))),
        level_chips, overflow)
    }

    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        shiny::span(class = "param-key", key)
      ),
      shiny::div(class = "param-values", chips)
    )
  })

  shiny::tagList(
    shiny::div(class = "inspector-section-title", "Inline reference paths"),
    shiny::div(class = "param-list", rows)
  )
}

# Reference chips for a generic (unrecognised) list: top-level access paths only.
render_generic_list_chips <- function(obj, list_name) {
  nms   <- names(obj)
  types <- vapply(obj, function(x) class(x)[1], character(1))

  rows <- lapply(seq_along(nms), function(i) {
    path <- paste0(list_name, "$", nms[i])
    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        shiny::span(class = "param-original", nms[i]),
        shiny::span(class = "param-key chip-muted", types[i])
      ),
      shiny::div(class = "param-values",
        value_chip("path", nms[i], path)
      )
    )
  })

  shiny::tagList(
    shiny::div(class = "inspector-section-title",
      paste0("List - ", length(nms), " elements")),
    shiny::div(class = "param-list", rows)
  )
}

# Bottom table for a model-derived list: dynamically uses available columns
render_model_list_table <- function(obj) {
  if (length(obj) == 0) return(shiny::div())

  keys <- names(obj)
  first <- obj[[1]]
  col_names <- setdiff(names(first), "parameter")

  body_rows <- lapply(keys, function(key) {
    el <- obj[[key]]
    cells <- lapply(col_names, function(col) {
      val <- el[[col]] %||% ""
      shiny::tags$td(val)
    })
    shiny::tags$tr(c(list(shiny::tags$td(class = "tbl-key", key)), cells))
  })

  headers <- c("Parameter", col_names)

  shiny::div(class = "preview-table-wrap",
    shiny::tags$table(class = "preview-table",
      shiny::tags$thead(shiny::tags$tr(
        lapply(headers, shiny::tags$th)
      )),
      shiny::tags$tbody(body_rows)
    )
  )
}

# Bottom table for a data-derived list: Variable | Type | Summary
render_data_list_table <- function(obj) {
  keys <- names(obj)

  body_rows <- lapply(keys, function(key) {
    el <- obj[[key]]
    if (!is.null(el$mean)) {
      type_lbl    <- "continuous"
      summary_txt <- paste0("M=", el$mean,
                            ", SD=", el$sd %||% "-",
                            ", N=", el$n  %||% "-")
    } else {
      type_lbl   <- "categorical"
      level_keys <- setdiff(names(el), c("n", "n_missing"))
      shown      <- level_keys[seq_len(min(3, length(level_keys)))]
      parts      <- unname(sapply(shown,
                           function(lk) paste0(lk, "=", el[[lk]]$pct, "%")))
      suffix <- if (length(level_keys) > 3)
        paste0(", +", length(level_keys) - 3, " more") else ""
      summary_txt <- paste0("N=", el$n %||% "", ": ",
                            paste(parts, collapse = ", "), suffix)
    }

    shiny::tags$tr(
      shiny::tags$td(class = "tbl-key",  key),
      shiny::tags$td(class = "tbl-type", type_lbl),
      shiny::tags$td(summary_txt)
    )
  })

  result <- shiny::div(class = "preview-table-wrap",
    shiny::tags$table(class = "preview-table",
      shiny::tags$thead(shiny::tags$tr(
        shiny::tags$th("Variable"),
        shiny::tags$th("Type"),
        shiny::tags$th("Summary")
      )),
      shiny::tags$tbody(unname(body_rows))
    )
  )
  result
}

# --- Scalar inspector ---
#
# Single-value variables (numeric, character, logical length-1 vectors).
# No prep step needed -- reference by the variable name directly.
render_scalar_inspector <- function(data) {
  nm  <- data$list_name
  val <- as.character(data$obj)

  shiny::div(style = "padding: 8px;",
    shiny::div(class = "refer-as-bar",
      "Refer to this value as ",
      shiny::tags$code(nm)
    ),
    shiny::div(class = "inspector-section-title", "Inline reference"),
    shiny::div(class = "param-list",
      shiny::div(class = "param-row",
        shiny::div(class = "param-names",
          shiny::span(class = "param-key", nm)
        ),
        shiny::div(class = "param-values",
          value_chip("value", val, nm)
        )
      )
    )
  )
}

render_unsupported <- function() {
  shiny::div(class = "inspector-unsupported",
    "This object type is not supported in draft v1.")
}

# --- modelbased inspector ---
#
# One chip row per result row (e.g. per contrast, per mean, per slope level).
# Row keys come from prep_modelbased(); value chips are built dynamically from
# whatever numeric columns the object provides — no column names hardcoded.
render_modelbased_inspector <- function(data) {
  if (is.null(data$mb_list)) {
    msg <- if (!is.null(data$error_msg)) data$error_msg else "unknown error"
    return(shiny::div(class = "inspector-error",
      shiny::strong("Could not prepare this modelbased object."),
      shiny::br(),
      shiny::span(style = "font-size:11px; color:#888;", msg)
    ))
  }

  mb_list   <- data$mb_list
  list_name <- data$list_name
  obj_class <- data$obj_class

  section_title <- switch(obj_class,
    estimate_means           = "Marginal Means",
    estimate_contrasts       = "Contrasts",
    estimate_slopes          = "Marginal Effects",
    estimate_slopes_summary  = "Marginal Effects",
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
        shiny::span(class = "param-key", key)
      ),
      shiny::div(class = "param-values", chips)
    )
  })

  shiny::div(class = "inspector-split",
    shiny::div(class = "inspector-top",
      shiny::div(class = "refer-as-bar",
        "Refer to this object as ",
        shiny::tags$code(paste0(list_name, "$..."))
      ),
      shiny::div(class = "inspector-section-title", section_title),
      do.call(shiny::div, c(list(class = "param-list"), rows))
    ),
    shiny::div(class = "inspector-bottom",
      shiny::div(class = "inspector-section-title", "Preview"),
      render_modelbased_table(mb_list)
    )
  )
}

# Compact table preview for modelbased objects.
render_modelbased_table <- function(mb_list) {
  if (length(mb_list) == 0) return(shiny::div())

  keys      <- names(mb_list)
  val_cols  <- names(mb_list[[1]])

  body_rows <- lapply(keys, function(key) {
    el    <- mb_list[[key]]
    cells <- lapply(val_cols, function(col) shiny::tags$td(el[[col]] %||% ""))
    shiny::tags$tr(c(list(shiny::tags$td(class = "tbl-key", key)), cells))
  })

  shiny::div(class = "preview-table-wrap",
    shiny::tags$table(class = "preview-table",
      shiny::tags$thead(shiny::tags$tr(
        lapply(c("", val_cols), shiny::tags$th)
      )),
      shiny::tags$tbody(body_rows)
    )
  )
}

# --- performance inspector ---
#
# model_performance: all metrics as chips on one row.
# compare_performance: one row per model, chips per metric.
# Column names come directly from the prep_performance() output — no hardcoding.
render_performance_inspector <- function(data) {
  if (is.null(data$perf_list)) {
    msg <- if (!is.null(data$error_msg)) data$error_msg else "unknown error"
    return(shiny::div(class = "inspector-error",
      shiny::strong("Could not prepare this performance object."),
      shiny::br(),
      shiny::span(style = "font-size:11px; color:#888;", msg)
    ))
  }

  perf_list <- data$perf_list
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
          shiny::span(class = "param-key", model_key)
        ),
        shiny::div(class = "param-values", chips)
      )
    })

    shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        shiny::div(class = "refer-as-bar",
          "Refer to this object as ",
          shiny::tags$code(paste0(list_name, "$..."))
        ),
        shiny::div(class = "inspector-section-title", "Model Comparison"),
        do.call(shiny::div, c(list(class = "param-list"), rows))
      ),
      shiny::div(class = "inspector-bottom",
        shiny::div(class = "inspector-section-title", "Preview"),
        render_modelbased_table(perf_list)
      )
    )

  } else {
    # Single model — flat list, all chips in one row
    base  <- paste0(list_name, "$")
    chips <- lapply(names(perf_list), function(col) {
      value_chip(col, perf_list[[col]], paste0(base, col))
    })

    shiny::div(class = "inspector-split",
      shiny::div(class = "inspector-top",
        shiny::div(class = "refer-as-bar",
          "Refer to this object as ",
          shiny::tags$code(paste0(list_name, "$..."))
        ),
        shiny::div(class = "inspector-section-title", "Model Performance"),
        shiny::div(class = "param-list",
          shiny::div(class = "param-row",
            shiny::div(class = "param-names",
              shiny::span(class = "param-key", "metrics")
            ),
            shiny::div(class = "param-values", chips)
          )
        )
      ),
      shiny::div(class = "inspector-bottom")
    )
  }
}

# --- Setup code block ---
#
# Renders the copyable R code the user pastes into their .qmd setup chunk.
render_setup_block <- function(code, list_name) {
  shiny::div(class = "setup-block",
    shiny::div(class = "setup-block-header",
      shiny::span(class = "setup-label", "Add to your setup chunk:"),
      shiny::tags$button(
        class            = "btn-copy-setup",
        `data-clipboard` = code,
        title            = "Copy setup code",
        "Copy"
      )
    ),
    shiny::tags$pre(class = "setup-code", code)
  )
}
