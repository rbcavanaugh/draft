# render_env_panel.R
#
# Builds the HTML for Panel 1 (the environment object list). Shows only objects
# the inspector can handle: parameters_model, modelbased, performance, data frames,
# and scalar values. Lists and other types are filtered out.
#
# Type badges map to CSS classes: badge-parameters_model, badge-dataframe, etc.
# giving each a distinct colour in styles.css.

render_object_list <- function(objs, selected_nm) {
  type_labels <- c(
    parameters_model = "M",
    modelbased       = "MB",
    performance      = "P",
    dataframe        = "D",
    scalar           = "V"
  )

  objs <- objs[objs$type %in% c("parameters_model", "modelbased", "performance", "dataframe", "scalar"), ]

  if (nrow(objs) == 0) {
    return(shiny::div(class = "empty-state",
      "No parameters, data frames, or single values found."))
  }

  # Sort by type order
  type_order <- c("parameters_model", "modelbased", "performance", "dataframe", "scalar")
  objs$type_factor <- factor(objs$type, levels = type_order)
  objs <- objs[order(objs$type_factor), ]
  objs$type_factor <- NULL

  rows <- lapply(seq_len(nrow(objs)), function(i) {
    nm         <- objs$name[i]
    type       <- objs$type[i]
    badge_text <- type_labels[type]
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
