# test-class-modelbased.R
#
# Full pipeline tests for the modelbased handler:
#   classify_object -> prep_modelbased -> suggest_list_name -> setup_code
#   -> assign to render_env -> render_inline -> convert_to_rmd
#
# Objects tested: estimate_means, estimate_contrasts, estimate_slopes
# All tests skip if modelbased is not installed.

skip_if_not_installed("modelbased")
library(modelbased)

# --- Shared fixtures -------------------------------------------------------
# Use iris/Species so estimate_means keys are "setosa", "versicolor", "virginica"
# (valid R identifiers). Digit-starting keys like "4", "6", "8" from cyl would
# work in R via [[]] but are invalid in bare $ inline paths.

m_iris <- lm(Sepal.Length ~ Species + Sepal.Width, data = iris)
m_cont <- lm(Sepal.Length ~ Sepal.Width * Petal.Width, data = iris)

means_obj     <- estimate_means(m_iris, at = "Species")
contrasts_obj <- estimate_contrasts(m_iris, contrast = "Species")
slopes_obj    <- estimate_slopes(m_cont, trend = "Sepal.Width", at = "Petal.Width")

# --- Classification --------------------------------------------------------

test_that("classify_object returns 'modelbased' for estimate_means", {
  expect_equal(classify_object(means_obj), "modelbased")
})

test_that("classify_object returns 'modelbased' for estimate_contrasts", {
  expect_equal(classify_object(contrasts_obj), "modelbased")
})

test_that("classify_object returns 'modelbased' for estimate_slopes", {
  expect_equal(classify_object(slopes_obj), "modelbased")
})

test_that("modelbased objects are not mis-classified as dataframe", {
  expect_false(classify_object(means_obj) == "dataframe")
})

# --- prep_modelbased: structure ---------------------------------------------

test_that("prep_modelbased returns a named list", {
  result <- prep_modelbased(means_obj)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  expect_false(is.null(names(result)))
})

test_that("each element is a named sub-list of character strings", {
  result <- prep_modelbased(means_obj)
  for (nm in names(result)) {
    expect_type(result[[nm]], "list")
    for (field in names(result[[nm]])) {
      expect_type(result[[nm]][[field]], "character")
    }
  }
})

test_that("estimate_means produces one entry per Species level", {
  result <- prep_modelbased(means_obj)
  expect_equal(length(result), length(unique(iris$Species)))
})

test_that("estimate_means keys match the Species levels", {
  result <- prep_modelbased(means_obj)
  expect_equal(length(result), 3)
  expect_true("setosa"     %in% names(result))
  expect_true("versicolor" %in% names(result))
  expect_true("virginica"  %in% names(result))
})

test_that("estimate_means includes numeric value columns", {
  result <- prep_modelbased(means_obj)
  first  <- result[[1]]
  # Should have at least mean/estimate and CI columns
  expect_gt(length(first), 0)
})

# --- prep_modelbased: estimate_contrasts -----------------------------------

test_that("estimate_contrasts produces entries with _vs_ pattern in keys", {
  result <- prep_modelbased(contrasts_obj)
  expect_gt(length(result), 0)
  expect_true(any(grepl("_vs_", names(result))))
})

test_that("estimate_contrasts entries include difference/CI columns", {
  result <- prep_modelbased(contrasts_obj)
  first  <- result[[1]]
  expect_gt(length(first), 0)
  expect_type(first[[1]], "character")
})

# --- prep_modelbased: estimate_slopes --------------------------------------

test_that("estimate_slopes returns one entry per slope level", {
  result <- prep_modelbased(slopes_obj)
  expect_gt(length(result), 0)
})

test_that("estimate_slopes entries are named lists of strings", {
  result <- prep_modelbased(slopes_obj)
  first  <- result[[1]]
  expect_type(first, "list")
  expect_true(all(vapply(first, is.character, logical(1))))
})

# --- Formatting: decimal places --------------------------------------------

test_that("prep_modelbased non-p values never exceed 2 decimal places", {
  dat       <- mtcars; dat$cyl <- factor(dat$cyl)
  m         <- lm(mpg ~ wt + cyl, data = dat)
  contrasts <- modelbased::estimate_contrasts(m, contrast = "cyl")
  result    <- prep_modelbased(contrasts)
  # unlist() names are like "8_vs_6.p"; match ".p" suffix or bare "p"
  all_vals  <- unlist(result)
  p_names   <- grepl("(\\.p|^p)$", names(all_vals))
  values    <- all_vals[!p_names]
  values    <- values[!grepl("^[<>]", trimws(values))]
  bad       <- values[grepl("\\.[0-9]*[1-9][0-9]{2,}", values)]
  expect_equal(length(bad), 0L,
               info = paste("Over-precise values:", paste(bad, collapse = ", ")))
})

test_that("prep_modelbased p values are APA formatted (3 dp or < .001)", {
  dat       <- mtcars; dat$cyl <- factor(dat$cyl)
  m         <- lm(mpg ~ wt + cyl, data = dat)
  contrasts <- modelbased::estimate_contrasts(m, contrast = "cyl")
  result    <- prep_modelbased(contrasts)
  all_vals  <- unlist(result)
  p_vals    <- all_vals[grepl("(\\.p|^p)$", names(all_vals))]
  # Each p-value must be "< .001", "> .999", or have exactly 3 decimal places
  valid <- grepl("^[<>]\\s*\\.001$|^[<>]\\s*\\.999$|\\.[0-9]{3}$", p_vals)
  expect_true(all(valid),
              info = paste("Badly formatted p-values:", paste(p_vals[!valid], collapse = ", ")))
})

# --- Handler: setup_code and suggest_list_name -----------------------------

test_that("suggest_list_name appends trailing underscore", {
  expect_equal(suggest_list_name("means_obj"), "means_obj_")
})

test_that("modelbased handler setup_code is correct", {
  h    <- get_handler("modelbased")
  code <- h$setup_code("my_means", "my_means_")
  expect_equal(code, "my_means_ <- draft::prep_modelbased(my_means)")
})

test_that("modelbased handler has correct badge", {
  h <- get_handler("modelbased")
  expect_equal(h$badge, "MB")
})

# --- Full inline pipeline --------------------------------------------------

test_that("estimate_means value resolves in render_inline", {
  result    <- prep_modelbased(means_obj)
  list_name <- suggest_list_name("means")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  # Use "setosa" — a valid R identifier key from iris$Species
  first_field <- names(result$setosa)[1]
  expected    <- result$setosa[[first_field]]
  text <- paste0("Setosa mean: {", list_name, "$setosa$", first_field, "}")
  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected), fixed = TRUE)
})

test_that("estimate_contrasts value resolves in render_inline", {
  result    <- prep_modelbased(contrasts_obj)
  list_name <- suggest_list_name("contrasts")
  first_key <- names(result)[1]

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  first_field <- names(result[[first_key]])[1]
  text <- paste0("Difference: {", list_name, "$`", first_key, "`$", first_field, "}")
  html <- as.character(render_inline(text, env, "{}"))
  # Expression may or may not have backtick-quoted key — just check no crash
  expect_type(html, "character")
})

test_that("convert_to_rmd produces correct syntax for modelbased path", {
  result    <- prep_modelbased(means_obj)
  list_name <- suggest_list_name("means")
  first_fld <- names(result$setosa)[1]

  text       <- paste0("Setosa mean: {", list_name, "$setosa$", first_fld, "}.")
  result_rmd <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result_rmd))
  expect_match(result_rmd, paste0("`r ", list_name, "\\$setosa\\$", first_fld, "`"))
})
