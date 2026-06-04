# sample_data.R
#
# Provides a small set of demo objects that are injected into the session
# environment when the user launches the app with an empty environment.
# Gives new users something to explore immediately.
#
# Objects created:
#   sample_lm_params  — model_parameters() output from a simple lm
#   sample_means      — estimate_means() output (marginal means by Species)
#   sample_corr       — correlation() output on numeric iris columns
#   sample_data       — plain data frame (iris numeric columns)

load_sample_objects <- function(env) {
  tryCatch({

    m <- stats::lm(Sepal.Length ~ Petal.Length + Species, data = datasets::iris)

    # parameters — works with base parameters package (always available)
    if (requireNamespace("parameters", quietly = TRUE)) {
      env$sample_lm_params <- parameters::model_parameters(m)
    }

    # modelbased — marginal means by Species
    if (requireNamespace("modelbased", quietly = TRUE)) {
      env$sample_means <- modelbased::estimate_means(m, at = "Species")
    }

    # correlation — on numeric iris columns
    if (requireNamespace("correlation", quietly = TRUE)) {
      env$sample_corr <- correlation::correlation(datasets::iris[, 1:4])
    }

    # plain data frame — always works
    env$sample_data <- datasets::iris[, 1:4]

  }, error = function(e) {
    # If sample objects fail for any reason, silently continue —
    # the user will just see the empty-state message.
  })
}
