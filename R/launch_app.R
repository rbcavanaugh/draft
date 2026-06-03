# launch_app.R
#
# Entry point for the repro package. Captures the calling environment so the
# Shiny app has access to all objects the user has in their R session without
# requiring them to write any additional code.
#
# The captured environment is stored in a package-level variable (.draft_env)
# so app_server() can retrieve it without Shiny reactive infrastructure needing
# to pass it explicitly.
#
# Static assets (CSS, JS) are registered via addResourcePath() under the
# "draft" prefix so they resolve correctly regardless of working directory.

.draft_env <- new.env(parent = emptyenv())

#' Launch the repro inline reporting app
#'
#' Call this from your R session after running your analysis chunks. The app
#' will have access to all objects in your global environment.
#'
#' @param env The environment to read objects from. Defaults to globalenv().
#' @param port Port to run the app on. Defaults to a random available port.
#' @param launch.browser Whether to open a browser automatically.
#'
#' @export
launch_app <- function(env = globalenv(), port = NULL, launch.browser = TRUE) {
  .draft_env$session_env <- env

  shiny::addResourcePath(
    prefix = "draft",
    directoryPath = system.file("www", package = "draft")
  )

  shiny::runApp(
    appDir        = shiny::shinyApp(ui = app_ui(), server = app_server),
    port          = port,
    launch.browser = launch.browser
  )
}

#' Retrieve the captured session environment
#'
#' Used internally by app_server to access the user's objects.
#'
#' @export
#' @keywords internal
get_session_env <- function() {
  if (is.null(.draft_env$session_env)) globalenv() else .draft_env$session_env
}
