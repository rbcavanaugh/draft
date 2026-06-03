# prep_model.R
#
# prep_params() is the primary exported function for preparing a parameters_model
# object for inline reporting. It formats and converts each row of the parameters
# data frame into a named sub-list so values are accessible via short, readable
# paths like results$age$estimate or results$age$ci.
#
# The returned list is keyed by sanitized parameter names. Each element
# contains all available fields for that parameter; fields not applicable to
# the model type (e.g. pd for frequentist models) are omitted rather than
# returned as NA, keeping the list clean.
#
# When effects = "all" (mixed models), fixed and random parameters are returned
# in the same flat list. Keys are unique because parameter names differ between
# fixed and random components. The effects and group fields on each sub-list
# let users distinguish them if needed.

#' Prepare parameters object for inline reporting
#'
#' Formats a parameters_model object into a nested named list suitable for
#' inline R Markdown / Quarto reporting.
#'
#' @param params_obj A parameters_model object from `parameters::model_parameters()`.
#'
#' @return A named list with one element per parameter. Each element is itself
#'   a named list containing formatted strings for all available fields.
#'
#' @export
#' @keywords internal
prep_params <- function(params_obj) {
  raw <- format(params_obj, zap_small = TRUE) |> dplyr::bind_rows()
  names(raw) <- tolower(names(raw))
  names(raw) <- gsub("\\s+", "_", names(raw))
  names(raw) <- gsub("[^a-z0-9_]", "", names(raw))

  # Create key: use parameter if it exists, otherwise combine parameter1 and parameter2
  if ("parameter" %in% names(raw)) {
    raw$key <- sanitize_key(raw$parameter)
  } else if ("parameter1" %in% names(raw) && "parameter2" %in% names(raw)) {
    raw$key <- sanitize_key(paste(raw$parameter1, raw$parameter2, sep = "_"))
  } else {
    stop("Could not find parameter column(s) to create keys")
  }

  params_df_to_list(raw)
}

#' Convert parameters data frame to nested list
#' @export
#' @keywords internal
params_df_to_list <- function(params) {
  result <- vector("list", nrow(params))
  names(result) <- params$key

  for (i in seq_len(nrow(params))) {
    row <- params[i, ]
    sub <- list()

    # Add any non-NA columns (values already formatted by format())
    for (col in names(row)) {
      if (col != "key" && is_present(row[[col]])) {
        sub[[col]] <- row[[col]]
      }
    }

    result[[i]] <- sub
  }

  result
}

# Returns TRUE if a value is non-NA and non-empty-string.
is_present <- function(x) {
  !is.na(x) && nzchar(as.character(x))
}
