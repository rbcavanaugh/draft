# app_ui.R
#
# Top-level UI function for the draft Shiny app. Defines the three-panel layout:
#   Panel 1 (left)    --  environment browser
#   Panel 2 (centre)  --  object inspector
#   Panel 3 (right)   --  text editor + live preview
#
# CSS and JS are loaded from inst/www/ via addResourcePath() in launch_app().

app_ui <- function() {
  bslib::page_fillable(
    shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", type = "text/css", href = "draft/styles.css"),
      shiny::tags$script(src = "draft/clipboard.js")
    ),

    # App header
    shiny::div(class = "app-header",
      shiny::div(class = "app-title", "draft"),
      shiny::div(class = "app-subtitle", "inline reporting helper"),
      shiny::div(class = "header-reminder",
        shiny::tags$em("Always re-render your full document to confirm reproducibility.")
      )
    ),

    # Three-panel body with collapsible sidebar for Panel 1
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        shiny::div(class = "panel panel-env",
          shiny::div(class = "panel-header",
            shiny::span("Environment")
          ),
          shiny::div(class = "panel-body",
            shiny::uiOutput("env_object_list")
          )
        )
      ),

      shiny::div(class = "panels-container",
        # Panel 2  --  Object Inspector
        shiny::div(class = "panel panel-inspector",
          shiny::div(class = "panel-header",
            shiny::span("Object Inspector"),
            shiny::uiOutput("inspector_controls")
          ),
          shiny::div(class = "panel-body",
            shiny::uiOutput("inspector_content")
          )
        ),

        # Panel 3  --  Text Editor + Live Preview
        shiny::div(class = "panel panel-editor",
          shiny::div(class = "panel-header",
            shiny::span("Results Text"),
            shiny::actionButton("settings_toggle", label = NULL, icon = shiny::icon("gear"),
                                class = "btn-settings", title = "Expression syntax settings")
          ),
          shiny::div(class = "panel-body",
            render_editor_panel_body()
          )
        )
      )
    )
  )
}
