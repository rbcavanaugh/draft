# render_env_panel.R
#
# Builds the HTML for Panel 1 (the environment object list). Shows objects
# whose types are registered in the handler registry plus scalar values.
# Lists and "other" types are filtered out.
#
# Badge text and type ordering come directly from the handler registry so
# adding a new class never requires editing this file.

render_object_list <- function(objs, selected_nm,
                               search_text = "", active_type = character(0)) {
  handlers   <- get_all_handlers()
  priorities <- vapply(handlers, function(h) h$priority, integer(1))
  ordered    <- handlers[order(priorities)]

  # Registered types in priority order, plus scalar
  registered_types <- names(ordered)
  visible_types    <- c(registered_types, "scalar")

  # Badge text from registry; scalar gets "V"
  badge_map <- stats::setNames(
    c(vapply(ordered, function(h) h$badge, character(1)), "V"),
    visible_types
  )

  objs <- objs[objs$type %in% visible_types, ]

  if (nrow(objs) == 0) {
    return(shiny::div(class = "empty-state-error",
      "No supported objects found in environment."))
  }

  # Apply type badge filter (additive — show union of selected types)
  if (length(active_type) > 0) {
    objs <- objs[objs$type %in% active_type, ]
  }

  # Apply name search filter (case-insensitive substring)
  if (!is.null(search_text) && nzchar(trimws(search_text))) {
    objs <- objs[grepl(trimws(search_text), objs$name, ignore.case = TRUE), ]
  }

  if (nrow(objs) == 0) {
    return(shiny::div(class = "empty-state", "No objects match the current filter."))
  }

  objs$type_factor <- factor(objs$type, levels = visible_types)
  objs <- objs[order(objs$type_factor), ]
  objs$type_factor <- NULL

  rows <- lapply(seq_len(nrow(objs)), function(i) {
    nm         <- objs$name[i]
    type       <- objs$type[i]
    badge_text <- badge_map[[type]]
    is_active  <- !is.null(selected_nm) && nm == selected_nm

    row_class <- paste("obj-row", if (is_active) "obj-row-active" else "")
    btn_id    <- paste0("obj_", nm)

    shiny::div(class = row_class,
      shiny::actionButton(btn_id, label = NULL, class = "obj-row-click-target"),
      shiny::span(class = paste0("type-badge badge-", type), badge_text),
      shiny::div(class = "obj-info",
        shiny::div(class = "obj-name", nm),
        shiny::div(class = "obj-meta", objs$class_label[i], "-", objs$size_label[i])
      )
    )
  })

  shiny::div(class = "obj-list", rows)
}

render_type_filter_badges <- function(objs) {
  handlers   <- get_all_handlers()
  priorities <- vapply(handlers, function(h) h$priority, integer(1))
  ordered    <- handlers[order(priorities)]

  registered_types <- names(ordered)
  visible_types    <- c(registered_types, "scalar")

  badge_map <- stats::setNames(
    c(vapply(ordered, function(h) h$badge, character(1)), "V"),
    visible_types
  )

  # Only show badges for types actually present in the environment
  present_types <- intersect(visible_types, unique(objs$type))

  if (length(present_types) <= 1) return(shiny::div())  # no point filtering one type

  badges <- lapply(present_types, function(type) {
    shiny::tags$button(
      class            = paste0("type-filter-badge badge-", type),
      `data-type`      = type,
      `onclick`        = "draftToggleTypeFilter(this)",
      badge_map[[type]]
    )
  })

  shiny::div(class = "env-type-filter-row", badges)
}
