# render_editor_panel.R
#
# Builds the Panel 3 UI: settings box, textarea, live preview, and copy footer.
#
# The settings box is toggled by the gear button in the panel header. It holds
# the delimiter radio buttons and is hidden by default.
#
# The live preview div is populated server-side by render_inline(). It sits
# below the textarea and updates reactively as the user types.
#
# A hidden <pre> element (id="rmd-output") always holds the current textarea
# content with delimiters converted to `r expr` syntax. The copy button's JS
# reads this element directly, avoiding a second server round-trip.

render_editor_panel_body <- function() {
  shiny::tagList(

    # Settings box  --  hidden until gear button clicked
    shiny::div(
      id    = "settings-box",
      class = "settings-box",
      style = "display:none;",
      shiny::div(class = "settings-title", "Inline expression syntax"),
      shiny::radioButtons(
        inputId  = "delimiter_choice",
        label    = NULL,
        choices  = c(
          "{expr} (default)" = "{}",
          "{{expr}}"         = "{{}}",
          "`r expr`"         = "`r`"
        ),
        selected = "{}",
        inline   = FALSE
      ),
      shiny::div(class = "settings-hint",
        "On copy, all expressions are converted to ",
        shiny::tags$code("`r expr`"), " syntax."
      )
    ),

    # Textarea
    shiny::div(class = "editor-wrap",
      shiny::tags$textarea(
        id          = "editor_text",
        class       = "editor-textarea",
        placeholder = "Write your results here. Use {expr} to embed inline values, e.g. {results_m1$age$estimate}",
        rows        = 10
      )
    ),

    # Live preview
    shiny::div(class = "preview-label", "Preview"),
    shiny::uiOutput("editor_preview"),

    # Setup chunk copy button -- shown when a model or data frame is selected
    shiny::uiOutput("setup_chunk_ui"),

    # Footer: copy button + hint
    shiny::div(class = "editor-footer",
      shiny::tags$button(
        id      = "copy-rmd-btn",
        class   = "btn-copy-rmd",
        onclick = "copyRmdText()",
        shiny::icon("copy"), " Copy inline code"
      ),
      shiny::span(class = "editor-footer-hint",
        "Copies text with ", shiny::tags$code("`r expr`"), " syntax"
      )
    ),

    # Hidden element holding the rmd-converted text for the copy button
    shiny::tags$pre(
      id    = "rmd-output",
      style = "display:none;",
      shiny::textOutput("rmd_text", inline = TRUE)
    )
  )
}
