# classify_objects.R
#
# Functions for inspecting the user's R environment and classifying objects
# into types the app knows how to handle. Classification drives which Panel 2
# display mode is used and what list-building path is offered.
#
# Types:
#   "parameters_model" - inherits from parameters_model (output of model_parameters())
#   "dataframe"        - data.frame or tibble
#   "list"             - named list
#   "scalar"           - atomic length-1 vector
#   "other"            - anything else; shown greyed out in the UI

#' List objects in environment
#' @export
#' @keywords internal
# Returns a data frame describing all user-visible objects in the given
# environment. Columns: name, type, class_label (human-readable), size_label.
# Objects starting with "." are excluded as they are typically hidden/internal.
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
      class_label <- make_class_label(obj, type)
      size_label  <- make_size_label(obj, type)
      data.frame(name=nm, type=type, class_label=class_label,
                 size_label=size_label, stringsAsFactors=FALSE)
    }, error = function(e) {
      data.frame(name=nm, type="other", class_label="?", size_label="",
                 stringsAsFactors=FALSE)
    })
  })

  do.call(rbind, results)
}

#' Classify object type
#' @export
#' @keywords internal
# Classifies a single object into one of five types.
# For model detection, attempts model_parameters() in a tryCatch rather than
# relying on class checks alone  --  this is more robust across the wide variety
# of model classes that parameters supports.
classify_object <- function(obj) {
  if (inherits(obj, "parameters_model")) return("parameters_model")
  # modelbased and performance checks before data.frame — they inherit from it
  if (inherits(obj, c("estimate_means", "estimate_contrasts", "estimate_slopes"))) return("modelbased")
  if (inherits(obj, c("performance_model", "compare_performance"))) return("performance")
  if (is.data.frame(obj)) return("dataframe")
  if (is.list(obj) && !is.null(names(obj))) return("list")
  if (is.atomic(obj) && length(obj) == 1) return("scalar")
  "other"
}

# Produces a short human-readable class string for display in the UI badge.
make_class_label <- function(obj, type) {
  switch(type,
    parameters_model = "parameters",
    dataframe        = if (inherits(obj, "tbl")) "tibble" else "data.frame",
    modelbased       = class(obj)[1],
    performance      = class(obj)[1],
    list             = "list",
    scalar           = class(obj)[1],
    other            = class(obj)[1]
  )
}

# Produces a short size description: rows x cols for data frames,
# n parameters for models, length for lists.
make_size_label <- function(obj, type) {
  switch(type,
    dataframe        = paste0(nrow(obj), " x ", ncol(obj)),
    parameters_model = paste0(nrow(obj), " parameters"),
    modelbased       = paste0(nrow(obj), " rows"),
    performance      = if (inherits(obj, "compare_performance")) paste0(nrow(obj), " models") else "1 model",
    list             = paste0(length(obj), " elements"),
    scalar           = as.character(obj),
    other            = ""
  )
}

# Detects whether a named list looks like prep_model output ("model_list"),
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
