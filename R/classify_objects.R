# classify_objects.R
#
# Functions for inspecting the user's R environment and classifying objects
# into types the app knows how to handle. Classification is driven by the
# handler registry in handlers.R - adding a new class only requires a
# R/class_*.R file with a register_handler() call that includes a detect
# function; no changes here are needed.
#
# Types not in the registry:
#   "scalar" - atomic length-1 vector
#   "list"   - named list
#   "other"  - anything else; shown greyed out in the UI

#' List objects in an environment
#'
#' Returns a data frame describing all user-visible objects in the given
#' environment. Objects whose names start with "." are excluded.
#'
#' @param env An environment. Defaults to `globalenv()`.
#'
#' @return A data frame with columns: `name`, `type`, `class_label`,
#'   `size_label`. One row per visible object.
#'
#' @export
#' @keywords internal
list_objects <- function(env = globalenv()) {
  nms <- ls(envir = env)
  nms <- nms[!startsWith(nms, ".")]

  if (length(nms) == 0) {
    return(data.frame(
      name        = character(),
      type        = character(),
      class_label = character(),
      size_label  = character(),
      stringsAsFactors = FALSE
    ))
  }

  results <- lapply(nms, function(nm) {
    tryCatch({
      obj         <- get(nm, envir = env)
      type        <- classify_object(obj)
      handler     <- get_handler(type)
      class_label <- if (!is.null(handler)) handler$class_label(obj) else make_fallback_class_label(obj, type)
      size_label  <- if (!is.null(handler)) handler$size_label(obj)  else make_fallback_size_label(obj, type)
      data.frame(name = nm, type = type, class_label = class_label,
                 size_label = size_label, stringsAsFactors = FALSE)
    }, error = function(e) {
      data.frame(name = nm, type = "other", class_label = "?", size_label = "",
                 stringsAsFactors = FALSE)
    })
  })

  do.call(rbind, results)
}

#' Classify an object into a draft type string
#'
#' Walks the handler registry in priority order and returns the type string
#' of the first matching handler. Falls back to `"scalar"`, `"list"`, or
#' `"other"` for objects not covered by any registered handler.
#'
#' @param obj Any R object.
#'
#' @return A single character string: a registered handler type (e.g.
#'   `"parameters_model"`, `"dataframe"`) or `"scalar"`, `"list"`, `"other"`.
#'
#' @export
#' @keywords internal
classify_object <- function(obj) {
  handlers   <- get_all_handlers()
  priorities <- vapply(handlers, function(h) h$priority, integer(1))
  ordered    <- handlers[order(priorities)]

  for (type in names(ordered)) {
    h <- ordered[[type]]
    if (!is.null(h$detect)) {
      detected <- tryCatch(h$detect(obj), error = function(e) FALSE)
      if (isTRUE(detected)) return(type)
    }
  }

  if (is.atomic(obj) && length(obj) == 1) return("scalar")
  if (is.list(obj) && !is.null(names(obj))) return("list")
  "other"
}

make_fallback_class_label <- function(obj, type) {
  switch(type,
    scalar = class(obj)[1],
    list   = "list",
    other  = class(obj)[1],
    class(obj)[1]
  )
}

make_fallback_size_label <- function(obj, type) {
  switch(type,
    list   = paste0(length(obj), " elements"),
    scalar = as.character(obj),
    other  = "",
    ""
  )
}

# Detects whether a named list looks like prep_params output ("model_list"),
# prep_data output ("data_list"), or a generic list. Drives the inspector's
# bottom preview panel.
detect_list_subtype <- function(obj) {
  if (length(obj) == 0 || !is.list(obj)) return("generic_list")
  first <- obj[[1]]
  if (!is.list(first)) return("generic_list")
  nms <- names(first)
  if ("estimate" %in% nms)          return("model_list")
  if (any(c("mean", "n") %in% nms)) return("data_list")
  "generic_list"
}
