# aaa_handlers.R
#
# Registry of class handlers. Each handler describes how the app detects,
# labels, preps, and renders one object class. Adding support for a new class
# means creating a R/class_*.R file and calling register_handler() - no changes
# to any shared infrastructure file are required.
#
# Prefixed "aaa_" so R sources this file before any R/class_*.R file, ensuring
# register_handler() is defined before the class files call it at load time.
#
# Handler fields:
#   priority      integer   lower = detected first in classify_object()
#   badge         character short label shown in the env panel
#   detect        function(obj)  returns TRUE if obj belongs to this type
#   class_label   function(obj)  human-readable class string for the env panel
#   size_label    function(obj)  short size description for the env panel
#   context       function(input)  extract Shiny input values needed by prep
#                 (default: empty list)
#   prep          function(obj, context)  convert object to named list for inline use
#   assign_result function(result)  extract the sub-object to store in render_env
#                 (default: whole result; dataframe handler uses result$summary)
#   setup_code    function(obj_name, list_name)  R code string for .qmd setup chunk
#   controls      function(nm, type)  Shiny UI for inspector header (default: NULL)
#   render        function(data)  Shiny UI for inspector body

.draft_handlers <- new.env(parent = emptyenv())

#' Register a class handler
#' @keywords internal
register_handler <- function(
  type,
  priority      = 100L,
  badge,
  detect,
  class_label,
  size_label,
  context       = function(input) list(),
  prep,
  assign_result = function(result) result,
  setup_code,
  controls      = function(nm, type) NULL,
  render
) {
  .draft_handlers[[type]] <- list(
    priority      = as.integer(priority),
    badge         = badge,
    detect        = detect,
    class_label   = class_label,
    size_label    = size_label,
    context       = context,
    prep          = prep,
    assign_result = assign_result,
    setup_code    = setup_code,
    controls      = controls,
    render        = render
  )
}

#' Retrieve a handler by type string. Returns NULL for unregistered types.
#' @keywords internal
get_handler <- function(type) {
  .draft_handlers[[type]]
}

#' Return all registered handlers as a list.
#' @keywords internal
get_all_handlers <- function() {
  as.list(.draft_handlers)
}
