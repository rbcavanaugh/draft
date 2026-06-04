# render_inspector_panel.R
#
# Builds Panel 2 (Object Inspector) UI. Receives a pre-computed `data` list
# from the server's inspector_data() reactive.
#
# Top-level dispatcher delegates to the handler registered for each type.
# Per-class renderers live in R/class_*.R files.
#
# Shared helpers used by all class renderers:
#   value_chip()      - single copyable path chip
#   refer_as_bar()    - "Refer to this object as X$..." banner
#   inspector_error() - standardised error display
#   preview_table()   - standard two-pane table

# --- Dispatcher ------------------------------------------------------------

render_inspector_content <- function(data) {
  handler <- get_handler(data$type)
  if (!is.null(handler)) return(handler$render(data))

  switch(data$type,
    scalar = render_scalar_inspector(data),
    list   = render_list_inspector(data),
    render_unsupported()
  )
}

# --- Shared helpers --------------------------------------------------------

# Renders the row label for a parameter/variable. Shows the sanitized key in
# purple monospace always (it's what users type). Shows the original human-
# readable name in navy only when it differs from the key — e.g. "Sepal.Length"
# vs "sepallength", or "wt × cyl" vs "wt__cyl". When they match, the extra
# label adds no information so it is suppressed.
# Renders the row label. show_original is a pre-computed flag for the whole
# object — TRUE if any row in this object has an original that differs from
# its key (so all rows render consistently within a single inspector view).
param_name_label <- function(original, key, show_original = FALSE) {
  if (!show_original) {
    return(shiny::span(class = "param-key", key))
  }
  shiny::tagList(
    shiny::span(class = "param-original", if (!is.null(original)) original else key),
    shiny::span(class = "param-key", key)
  )
}

# Returns TRUE if any original name in the vectors differs from its key —
# i.e., whether showing both columns adds any information for this object.
any_original_differs <- function(originals, keys) {
  any(!mapply(function(o, k) identical(trimws(as.character(o %||% k)), k),
              originals, keys))
}

# Renders a single value chip: label | formatted value | copy button.
value_chip <- function(label, value, path) {
  clipboard_text <- paste0("{", path, "}")
  shiny::div(class = "value-chip",
    shiny::span(class = "chip-label", label),
    shiny::span(class = "chip-value", value),
    shiny::tags$button(
      class            = "chip-copy",
      `data-clipboard` = clipboard_text,
      title            = paste("Copy:", clipboard_text),
      shiny::icon("copy")
    )
  )
}

# "Refer to this object as list_name$..." banner shown at the top of inspectors.
refer_as_bar <- function(list_name) {
  shiny::div(class = "refer-as-bar",
    "Refer to this object as ",
    shiny::tags$code(paste0(list_name, "$..."))
  )
}

# Standardised error display for when prep fails.
inspector_error <- function(title, msg) {
  shiny::div(class = "inspector-error",
    shiny::strong(title),
    shiny::br(),
    shiny::span(style = "font-size:11px; color:#888;", msg)
  )
}

# Renders a generic keyed-list preview table: one row per key, one column per
# value field. The first column header is blank (it holds the key). Used by
# modelbased, effectsize, performance, and any future class whose prep output
# is a named list of named sub-lists.
render_keyed_list_table <- function(lst) {
  if (length(lst) == 0) return(shiny::div())
  keys     <- names(lst)
  val_cols <- names(lst[[1]])
  body_rows <- lapply(keys, function(key) {
    el    <- lst[[key]]
    cells <- lapply(val_cols, function(col) shiny::tags$td(el[[col]] %||% ""))
    shiny::tags$tr(c(list(shiny::tags$td(class = "tbl-key", key)), cells))
  })
  preview_table(c("", val_cols), body_rows)
}

# Standard preview table used in inspector bottom panels.
preview_table <- function(headers, body_rows) {
  shiny::div(class = "preview-table-wrap",
    shiny::tags$table(class = "preview-table",
      shiny::tags$thead(shiny::tags$tr(lapply(headers, shiny::tags$th))),
      shiny::tags$tbody(body_rows)
    )
  )
}

# --- Scalar inspector ------------------------------------------------------

render_scalar_inspector <- function(data) {
  nm  <- data$list_name
  obj <- data$obj
  val <- format_scalar(obj)

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

# --- List inspector --------------------------------------------------------

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

render_model_list_chips <- function(obj, list_name) {
  rows <- lapply(names(obj), function(key) {
    el   <- obj[[key]]
    base <- paste0(list_name, "$", key, "$")

    chips <- Filter(Negate(is.null), list(
      if (!is.null(el$estimate)) value_chip("estimate", el$estimate, paste0(base, "estimate")),
      if (!is.null(el$ci))       value_chip("ci",       el$ci,       paste0(base, "ci")),
      if (!is.null(el$p))        value_chip("p",        el$p,        paste0(base, "p")),
      if (!is.null(el$pd))       value_chip("pd",       el$pd,       paste0(base, "pd"))
    ))

    shiny::div(class = "param-row",
      shiny::div(class = "param-names", shiny::span(class = "param-key", key)),
      shiny::div(class = "param-values", chips)
    )
  })

  shiny::tagList(
    shiny::div(class = "inspector-section-title", "Inline reference paths"),
    shiny::div(class = "param-list", rows)
  )
}

render_model_list_table <- function(obj) {
  if (length(obj) == 0) return(shiny::div())

  keys      <- names(obj)
  col_names <- setdiff(names(obj[[1]]), "parameter")

  body_rows <- lapply(keys, function(key) {
    el    <- obj[[key]]
    cells <- lapply(col_names, function(col) shiny::tags$td(el[[col]] %||% ""))
    shiny::tags$tr(c(list(shiny::tags$td(class = "tbl-key", key)), cells))
  })

  preview_table(c("Parameter", col_names), body_rows)
}

render_data_list_chips <- function(obj, list_name) {
  rows <- lapply(names(obj), function(key) {
    el   <- obj[[key]]
    base <- paste0(list_name, "$", key, "$")

    chips <- if (!is.null(el$mean)) {
      list(
        value_chip("mean",   el$mean,           paste0(base, "mean")),
        value_chip("sd",     el$sd   %||% "-",  paste0(base, "sd")),
        value_chip("median", el$median %||% "-", paste0(base, "median")),
        value_chip("n",      el$n    %||% "-",  paste0(base, "n"))
      )
    } else {
      level_keys  <- setdiff(names(el), c("n", "n_missing"))
      shown_keys  <- level_keys[seq_len(min(5, length(level_keys)))]
      level_chips <- lapply(shown_keys, function(lk) {
        value_chip(paste0(lk, " %"), paste0(el[[lk]]$pct, "%"), paste0(base, lk, "$pct"))
      })
      overflow <- if (length(level_keys) > 5)
        list(shiny::span(class = "chip-muted", paste0("+ ", length(level_keys) - 5, " more")))
      else list()
      c(list(value_chip("n", el$n %||% "-", paste0(base, "n"))), level_chips, overflow)
    }

    shiny::div(class = "param-row",
      shiny::div(class = "param-names", shiny::span(class = "param-key", key)),
      shiny::div(class = "param-values", chips)
    )
  })

  shiny::tagList(
    shiny::div(class = "inspector-section-title", "Inline reference paths"),
    shiny::div(class = "param-list", rows)
  )
}

render_data_list_table <- function(obj) {
  body_rows <- lapply(names(obj), function(key) {
    el <- obj[[key]]
    if (!is.null(el$mean)) {
      type_lbl    <- "continuous"
      summary_txt <- paste0("M=", el$mean, ", SD=", el$sd %||% "-", ", N=", el$n %||% "-")
    } else {
      type_lbl   <- "categorical"
      level_keys <- setdiff(names(el), c("n", "n_missing"))
      shown      <- level_keys[seq_len(min(3, length(level_keys)))]
      parts      <- unname(sapply(shown, function(lk) paste0(lk, "=", el[[lk]]$pct, "%")))
      suffix     <- if (length(level_keys) > 3) paste0(", +", length(level_keys) - 3, " more") else ""
      summary_txt <- paste0("N=", el$n %||% "", ": ", paste(parts, collapse = ", "), suffix)
    }
    shiny::tags$tr(
      shiny::tags$td(class = "tbl-key",  key),
      shiny::tags$td(class = "tbl-type", type_lbl),
      shiny::tags$td(summary_txt)
    )
  })

  preview_table(c("Variable", "Type", "Summary"), unname(body_rows))
}

render_generic_list_chips <- function(obj, list_name) {
  nms   <- names(obj)
  types <- vapply(obj, function(x) class(x)[1], character(1))

  rows <- lapply(seq_along(nms), function(i) {
    path <- paste0(list_name, "$", nms[i])
    shiny::div(class = "param-row",
      shiny::div(class = "param-names",
        param_name_label(nms[i], nms[i]),
        shiny::span(class = "chip-muted", types[i])
      ),
      shiny::div(class = "param-values",
        value_chip("path", nms[i], path)
      )
    )
  })

  shiny::tagList(
    shiny::div(class = "inspector-section-title", paste0("List - ", length(nms), " elements")),
    shiny::div(class = "param-list", rows)
  )
}

# --- Unsupported -----------------------------------------------------------

render_unsupported <- function() {
  shiny::div(class = "inspector-unsupported",
    "This object type is not supported in draft v1.")
}

# --- Setup code block ------------------------------------------------------

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
