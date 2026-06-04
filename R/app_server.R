# app_server.R
#
# Top-level server function. Keeps reactive plumbing minimal - delegates all
# rendering and data-shaping to helpers in R/render_*.R and R/class_*.R files.
#
# Reactive state:
#   env_objects     - objects visible in the user's R session
#   selected_object - currently selected object in Panel 1
#   render_env      - named lists accumulated from prep_* calls;
#                     parent is the user's session env so expressions can also
#                     reference raw session objects (e.g. mydata$age)
#
# inspector_data() unified shape (for handler-based types):
#   list(type, result, error_msg, list_name, setup_code, needs_assignment, obj_class)
# render() receives this whole list as `data`.

app_server <- function(input, output, session) {

  # --- Reactive state ---

  env_objects     <- shiny::reactiveVal(NULL)
  selected_object <- shiny::reactiveVal(NULL)
  active_type_filter <- shiny::reactiveVal(character(0))  # empty = show all

  # render_env inherits from the session env so Panel 3 expressions can reach
  # both the accumulated prep lists AND raw objects in the user's session.
  render_env <- new.env(parent = get_session_env())

  shiny::observe({
    session_env <- get_session_env()
    objs        <- list_objects(session_env)

    # If the user's environment has no supported objects, populate it with
    # sample objects so they can explore the app straight away.
    if (is.null(objs) || nrow(objs) == 0) {
      load_sample_objects(session_env)
      objs <- list_objects(session_env)
    }

    env_objects(objs)
  })


  # --- Panel 1: Environment object list ---

  # Type-filter badge toggle — JS calls Shiny.setInputValue("env_type_filter", type)
  shiny::observeEvent(input$env_type_filter, {
    incoming <- input$env_type_filter
    if (is.null(incoming) || !nzchar(incoming)) {
      active_type_filter(character(0))
    } else {
      active_type_filter(strsplit(incoming, ",", fixed = TRUE)[[1]])
    }
  })

  output$env_type_filters <- shiny::renderUI({
    objs <- env_objects()
    if (is.null(objs) || nrow(objs) == 0) return(shiny::div())
    render_type_filter_badges(objs)
  })

  output$env_object_list <- shiny::renderUI({
    objs <- env_objects()
    if (is.null(objs) || nrow(objs) == 0) {
      return(shiny::div(class = "empty-state-error",
        "No supported objects found in environment."))
    }
    render_object_list(
      objs,
      selected_object(),
      search_text = input$env_search  %||% "",
      active_type = active_type_filter() %||% character(0)
    )
  })

  # Route object-row clicks to selected_object(). Registers one observeEvent
  # per object name, but only once - tracked in registered_obs so that env
  # refreshes don't accumulate duplicate handlers for the same object.
  registered_obs <- list()
  shiny::observe({
    objs <- env_objects()
    if (is.null(objs) || nrow(objs) == 0) return()
    new_nms <- setdiff(objs$name, names(registered_obs))
    for (nm in new_nms) {
      local({
        local_nm <- nm
        registered_obs[[local_nm]] <<- shiny::observeEvent(
          input[[paste0("obj_", local_nm)]],
          { selected_object(local_nm) },
          ignoreInit = TRUE
        )
      })
    }
  })

  # --- Panel 2: Object inspector ---

  output$inspector_controls <- shiny::renderUI({
    nm <- selected_object()
    if (is.null(nm)) return(NULL)
    obj     <- get(nm, envir = get_session_env())
    type    <- tryCatch(classify_object(obj), error = function(e) "other")
    handler <- get_handler(type)
    if (!is.null(handler)) handler$controls(nm, type) else NULL
  })

  # Computes inspector data for the selected object using the handler registry.
  inspector_data <- shiny::reactive({
    nm <- selected_object()
    if (is.null(nm)) return(NULL)

    obj  <- get(nm, envir = get_session_env())
    type <- tryCatch(classify_object(obj), error = function(e) "other")

    handler <- get_handler(type)

    if (!is.null(handler)) {
      list_name  <- suggest_list_name(nm)
      context    <- c(handler$context(input), list(nm = nm))
      result_err <- NULL
      result     <- tryCatch(
        handler$prep(obj, context),
        error = function(e) { result_err <<- conditionMessage(e); NULL }
      )
      list(
        type             = type,
        result           = result,
        error_msg        = result_err,
        list_name        = list_name,
        setup_code       = handler$setup_code(nm, list_name),
        needs_assignment = !is.null(result),
        obj_class        = class(obj)[1]
      )

    } else if (type == "scalar") {
      list(type = "scalar", obj = obj, list_name = nm)

    } else if (type == "list") {
      list(
        type         = "list",
        obj          = obj,
        list_name    = nm,
        list_subtype = detect_list_subtype(obj)
      )

    } else {
      list(type = "other")
    }
  })

  # Assign prep output to render_env when inspector_data changes
  shiny::observeEvent(inspector_data(), {
    data <- inspector_data()
    if (is.null(data) || !isTRUE(data$needs_assignment)) return()

    handler <- get_handler(data$type)
    if (is.null(handler)) return()

    val <- handler$assign_result(data$result)
    if (!is.null(val)) assign(data$list_name, val, envir = render_env)
  })

  # Generate complete .qmd chunk including setup code for all referenced objects
  full_chunk <- shiny::reactive({
    text <- input$editor_text
    if (is.null(text) || !nzchar(text)) return(NULL)

    objs <- env_objects()
    if (is.null(objs) || nrow(objs) == 0) return(NULL)

    # Only objects with registered handlers need setup code
    handlers    <- get_all_handlers()
    typed_objs  <- objs[objs$type %in% names(handlers), ]
    if (nrow(typed_objs) == 0) return(NULL)

    setup_codes <- character()
    for (i in seq_len(nrow(typed_objs))) {
      obj_name  <- typed_objs$name[i]
      obj_type  <- typed_objs$type[i]
      list_name <- suggest_list_name(obj_name)
      handler   <- get_handler(obj_type)

      if (!is.null(handler) && grepl(paste0("\\b", gsub("[.]", "\\.", list_name), "\\b"), text)) {
        setup_codes <- c(setup_codes, handler$setup_code(obj_name, list_name))
      }
    }

    if (length(setup_codes) == 0) return(NULL)

    paste0("```{r}\n", paste(setup_codes, collapse = "\n"), "\n```")
  })

  # Renders the "Copy setup chunk" button in Panel 3 when a supported object
  # is selected. Scalars need no setup code so nothing is rendered for them.
  output$setup_chunk_ui <- shiny::renderUI({
    chunk <- full_chunk()
    if (is.null(chunk)) return(NULL)

    shiny::div(class = "setup-chunk-footer",
      shiny::tags$button(
        class            = "btn-copy-setup-chunk",
        `data-clipboard` = chunk,
        shiny::icon("code"), " Copy setup chunk"
      ),
      shiny::div(class = "setup-chunk-hint",
        "Paste into your setup chunk after fitting your model or loading your data"
      )
    )
  })

  output$inspector_content <- shiny::renderUI({
    nm <- selected_object()
    if (is.null(nm)) {
      return(shiny::div(class = "inspector-placeholder",
        shiny::div(class = "placeholder-title", "Select an object"),
        shiny::div(class = "placeholder-body",
          "Click a model, data frame, or single value to see ",
          "its inline reference paths."
        )
      ))
    }
    data <- inspector_data()
    if (is.null(data)) return(shiny::div(class = "empty-state", "Loading..."))
    tryCatch(
      render_inspector_content(data),
      error = function(e) {
        cat("ERROR in render_inspector_content:\n")
        cat("Message:", as.character(e), "\n")
        print(traceback())
        shiny::div(class = "inspector-error",
          shiny::strong("Error rendering inspector:"),
          shiny::br(),
          shiny::span(style = "font-size:11px; color:#c0392b;", as.character(e))
        )
      }
    )
  })

  # --- Panel 3: Text editor + live preview ---

  # Debounced editor text - avoids re-rendering on every keystroke
  editor_text_d <- shiny::reactive(input$editor_text) |> shiny::debounce(300)

  # Live preview: evaluate all inline expressions and render styled HTML.
  output$editor_preview <- shiny::renderUI({
    text <- editor_text_d()
    if (is.null(text) || !nzchar(text)) {
      return(shiny::div(class = "preview-empty",
                        "Preview will appear here as you type..."))
    }
    delim <- input$delimiter_choice %||% "{}"
    render_inline(text, render_env, delim)
  })

  # Converted text for copy button - always up to date, stored in hidden <pre>.
  # suspendWhenHidden = FALSE is required because the <pre> has display:none —
  # without it Shiny suspends this output and the copy button reads stale/empty text.
  output$rmd_text <- shiny::renderText({
    text <- input$editor_text
    if (is.null(text)) return("")
    delim <- input$delimiter_choice %||% "{}"
    convert_to_rmd(text, delim)
  })
  shiny::outputOptions(output, "rmd_text", suspendWhenHidden = FALSE)

}

# Null-coalescing operator
`%||%` <- function(lhs, rhs) if (is.null(lhs)) rhs else lhs
