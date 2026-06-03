# app_server.R
#
# Top-level server function. Keeps reactive plumbing minimal  --  delegates all
# rendering and data-shaping to helpers in R/render_*.R files.
#
# Reactive state:
#   env_objects     - objects visible in the user's R session
#   selected_object - currently selected object in Panel 1
#   render_env      - named lists accumulated from prep_model/prep_data calls;
#                     parent is the user's session env so expressions can also
#                     reference raw session objects (e.g. mydata$age)

app_server <- function(input, output, session) {

  # --- Reactive state ---

  env_objects     <- shiny::reactiveVal(NULL)
  selected_object <- shiny::reactiveVal(NULL)

  # render_env inherits from the session env so Panel 3 expressions can reach
  # both the accumulated prep lists AND raw objects in the user's session.
  render_env <- new.env(parent = get_session_env())

  shiny::observe({
    env_objects(list_objects(get_session_env()))
  })


  # --- Panel 1: Environment object list ---

  output$env_object_list <- shiny::renderUI({
    objs <- env_objects()
    if (is.null(objs) || nrow(objs) == 0) {
      return(shiny::div(class = "empty-state", "No objects found in environment."))
    }
    render_object_list(objs, selected_object())
  })

  # Route object-row clicks to selected_object(). Registers one observeEvent
  # per object name, but only once  --  tracked in registered_obs so that env
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
    obj  <- get(nm, envir = get_session_env())
    type <- tryCatch(classify_object(obj), error = function(e) "other")
    render_inspector_controls(nm, type)
  })

  # Computes inspector data for the selected object. For models and data frames,
  # uses pre-computed parameters (models) or computes on demand (dataframes).
  inspector_data <- shiny::reactive({
    nm <- selected_object()
    if (is.null(nm)) return(NULL)

    obj  <- get(nm, envir = get_session_env())
    type <- tryCatch(classify_object(obj), error = function(e) "other")

    if (type == "parameters_model") {
      list_name  <- suggest_list_name(nm, type)

      params_err <- NULL
      params_list <- tryCatch(
        prep_params(obj),
        error = function(e) {
          params_err <<- paste("Error formatting parameters:", conditionMessage(e))
          NULL
        }
      )

      setup_code <- generate_setup_code(nm, list_name)

      list(type = "parameters_model", params_list = params_list, error_msg = params_err,
           list_name = list_name, setup_code = setup_code, needs_assignment = !is.null(params_list))

    } else if (type == "dataframe") {
      mode       <- input$df_mode %||% "summary"
      list_name  <- suggest_list_name(nm, type)
      setup_code <- generate_data_setup_code(nm, list_name)

      if (mode == "summary") {
        summary_err <- NULL
        summary_list <- tryCatch(prep_data(obj),
                                error = function(e) { summary_err <<- as.character(e); NULL })

        list(type = "dataframe", mode = "summary",
             summary_list = summary_list, obj = obj,
             list_name = list_name, setup_code = setup_code, summary_err = summary_err)
      } else {
        list(type = "dataframe", mode = "raw",
             raw_df = raw_columns(obj, nm),
             list_name = list_name, setup_code = setup_code)
      }

    } else if (type == "modelbased") {
      list_name  <- suggest_list_name(nm, type)
      setup_code <- generate_modelbased_setup_code(nm, list_name)
      mb_err     <- NULL
      mb_list    <- tryCatch(
        prep_modelbased(obj),
        error = function(e) { mb_err <<- conditionMessage(e); NULL }
      )
      list(type = "modelbased", mb_list = mb_list, error_msg = mb_err,
           list_name = list_name, setup_code = setup_code,
           obj_class = class(obj)[1], needs_assignment = !is.null(mb_list))

    } else if (type == "performance") {
      list_name  <- suggest_list_name(nm, type)
      setup_code <- generate_performance_setup_code(nm, list_name)
      perf_err   <- NULL
      perf_list  <- tryCatch(
        prep_performance(obj),
        error = function(e) { perf_err <<- conditionMessage(e); NULL }
      )
      list(type = "performance", perf_list = perf_list, error_msg = perf_err,
           list_name = list_name, setup_code = setup_code,
           obj_class = class(obj)[1], needs_assignment = !is.null(perf_list))

    } else if (type == "scalar") {
      list(type = "scalar", obj = obj, list_name = nm)

    } else {
      list(type = "other")
    }
  })

  # Assign model/dataframe lists to render_env when inspector_data changes
  shiny::observeEvent(inspector_data(), {
    data <- inspector_data()
    if (is.null(data)) return()

    if (data$type == "parameters_model" && isTRUE(data$needs_assignment)) {
      assign(data$list_name, data$params_list, envir = render_env)
    } else if (data$type == "dataframe" && data$mode == "summary" && !is.null(data$summary_list)) {
      assign(data$list_name, data$summary_list, envir = render_env)
    } else if (data$type == "modelbased" && isTRUE(data$needs_assignment)) {
      assign(data$list_name, data$mb_list, envir = render_env)
    } else if (data$type == "performance" && isTRUE(data$needs_assignment)) {
      assign(data$list_name, data$perf_list, envir = render_env)
    }
  })

  # Generate complete .qmd chunk including setup code for all referenced objects
  full_chunk <- shiny::reactive({
    text <- input$editor_text
    if (is.null(text) || !nzchar(text)) return(NULL)

    delim <- input$delimiter_choice %||% "{}"
    objs <- env_objects()
    if (is.null(objs) || nrow(objs) == 0) return(NULL)

    # Filter to parameters_model and dataframe objects
    relevant_objs <- objs[objs$type %in% c("parameters_model", "dataframe", "modelbased", "performance"), ]
    if (nrow(relevant_objs) == 0) return(NULL)

    # Generate setup code for each object whose suggested name appears in the text
    setup_codes <- character()
    for (i in seq_len(nrow(relevant_objs))) {
      obj_name <- relevant_objs$name[i]
      obj_type <- relevant_objs$type[i]
      list_name <- suggest_list_name(obj_name, obj_type)

      # Check if this list name is referenced in the editor text
      if (grepl(paste0("\\b", gsub("[.]", "\\.", list_name), "\\b"), text)) {
        if (obj_type == "parameters_model") {
          setup_codes <- c(setup_codes, generate_setup_code(obj_name, list_name))
        } else if (obj_type == "dataframe") {
          setup_codes <- c(setup_codes, generate_data_setup_code(obj_name, list_name))
        } else if (obj_type == "modelbased") {
          setup_codes <- c(setup_codes, generate_modelbased_setup_code(obj_name, list_name))
        } else if (obj_type == "performance") {
          setup_codes <- c(setup_codes, generate_performance_setup_code(obj_name, list_name))
        }
      }
    }

    if (length(setup_codes) == 0) return(NULL)

    # Build code block with setup codes only
    paste0(
      "```{r}\n",
      paste(setup_codes, collapse = "\n"),
      "\n```"
    )
  })

  # Renders the "Copy setup chunk" button in Panel 3 when a model or data frame
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

  # Settings toggle is handled entirely in clipboard.js (no server round-trip).

  # Debounced editor text  --  avoids re-rendering on every keystroke
  editor_text_d <- shiny::reactive(input$editor_text) |> shiny::debounce(300)

  # Live preview: evaluate all inline expressions and render styled HTML.
  output$editor_preview <- shiny::renderUI({
    text  <- editor_text_d()
    if (is.null(text) || !nzchar(text)) {
      return(shiny::div(class = "preview-empty",
                        "Preview will appear here as you type..."))
    }
    delim <- input$delimiter_choice %||% "{}"
    render_inline(text, render_env, delim)
  })

  # Converted text for copy button  --  always up to date, stored in hidden <pre>
  output$rmd_text <- shiny::renderText({
    text  <- input$editor_text
    if (is.null(text)) return("")
    delim <- input$delimiter_choice %||% "{}"
    convert_to_rmd(text, delim)
  })

}

# Extract object names that are referenced in text (e.g., results_m_lm, data)
extract_referenced_names <- function(text, available_names) {
  referenced <- character()
  for (name in available_names) {
    if (grepl(paste0("\\b", gsub("[.]", "\\.", name), "\\b"), text)) {
      referenced <- c(referenced, name)
    }
  }
  referenced
}

# Null-coalescing operator
`%||%` <- function(lhs, rhs) if (is.null(lhs)) rhs else lhs
