#' Pre-compute model parameters on app startup
#' @keywords internal

precompute_model_params <- function(env) {
  objs <- ls(envir = env)
  objs <- objs[!startsWith(objs, ".")]

  lookup <- list()

  for (nm in objs) {
    obj <- tryCatch(get(nm, envir = env), error = function(e) NULL)
    if (is.null(obj)) next

    is_model <- tryCatch(insight::is_model(obj), error = function(e) FALSE)
    if (!is_model) next

    cached_name <- paste0(".model_params_", nm)
    cached_params <- tryCatch(
      parameters::model_parameters(obj),
      error = function(e) NULL
    )

    if (!is.null(cached_params)) {
      assign(cached_name, cached_params, envir = env)
      lookup[[nm]] <- cached_name
    }
  }

  lookup
}
