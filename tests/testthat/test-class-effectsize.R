# test-class-effectsize.R
#
# Full pipeline tests for the effectsize handler:
#   classify_object -> prep_effectsize -> suggest_list_name -> setup_code
#   -> assign to render_env -> render_inline -> convert_to_rmd
#
# Objects tested: effectsize_difference (cohens_d), effectsize_anova (eta_squared),
#                 effectsize_table (cramers_v)
# All tests skip if effectsize is not installed.

skip_if_not_installed("effectsize")
library(effectsize)

# --- Shared fixtures -------------------------------------------------------

es_diff  <- cohens_d(mpg ~ am, data = mtcars)          # single-row, no Parameter col
es_anova <- eta_squared(aov(mpg ~ cyl + gear, data = mtcars))  # multi-row, has Parameter col
es_assoc <- cramers_v(table(mtcars$cyl, mtcars$gear))  # single-row, no Parameter col

# --- Classification --------------------------------------------------------

test_that("classify_object returns 'effectsize' for effectsize_difference", {
  expect_equal(classify_object(es_diff), "effectsize")
})

test_that("classify_object returns 'effectsize' for effectsize_anova", {
  expect_equal(classify_object(es_anova), "effectsize")
})

test_that("classify_object returns 'effectsize' for effectsize_table", {
  expect_equal(classify_object(es_assoc), "effectsize")
})

test_that("effectsize objects are not mis-classified as dataframe", {
  expect_false(classify_object(es_diff)  == "dataframe")
  expect_false(classify_object(es_anova) == "dataframe")
})

# --- prep_effectsize: single-row (flat) ------------------------------------

test_that("prep_effectsize returns a flat named list for cohens_d", {
  result <- prep_effectsize(es_diff)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  # flat: values are character strings, not sub-lists
  expect_type(result[[1]], "character")
})

test_that("prep_effectsize flat result has no sub-lists", {
  result <- prep_effectsize(es_diff)
  expect_true(all(vapply(result, is.character, logical(1))))
})

test_that("prep_effectsize flat result values are character strings", {
  result <- prep_effectsize(es_diff)
  for (field in names(result)) {
    expect_type(result[[field]], "character")
  }
})

test_that("prep_effectsize flat result includes ci_low and ci_high", {
  result <- prep_effectsize(es_diff)
  expect_true("ci_low"  %in% names(result))
  expect_true("ci_high" %in% names(result))
})

test_that("prep_effectsize works for cramers_v", {
  result <- prep_effectsize(es_assoc)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  expect_true(all(vapply(result, is.character, logical(1))))
})

# --- prep_effectsize: multi-row (nested) -----------------------------------

test_that("prep_effectsize returns a nested named list for eta_squared", {
  result <- prep_effectsize(es_anova)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  # nested: each element is a sub-list
  expect_type(result[[1]], "list")
})

test_that("eta_squared produces one entry per predictor", {
  result <- prep_effectsize(es_anova)
  # aov(mpg ~ cyl + gear) -> two predictors
  expect_equal(length(result), 2)
})

test_that("eta_squared keys match predictor names", {
  result <- prep_effectsize(es_anova)
  expect_true("cyl"  %in% names(result))
  expect_true("gear" %in% names(result))
})

test_that("eta_squared nested entries are named lists of character strings", {
  result <- prep_effectsize(es_anova)
  for (nm in names(result)) {
    expect_type(result[[nm]], "list")
    for (field in names(result[[nm]])) {
      expect_type(result[[nm]][[field]], "character")
    }
  }
})

test_that("eta_squared entries include CI fields", {
  result <- prep_effectsize(es_anova)
  expect_true("ci_low"  %in% names(result$cyl))
  expect_true("ci_high" %in% names(result$cyl))
})

# --- Formatting: decimal places --------------------------------------------

test_that("prep_effectsize values never exceed 2 decimal places", {
  result <- prep_effectsize(es_diff)
  values <- unlist(result)
  values <- values[!grepl("^[<>]", trimws(values))]
  bad    <- values[grepl("\\.[0-9]*[1-9][0-9]{2,}", values)]
  expect_equal(length(bad), 0L,
               info = paste("Over-precise values:", paste(bad, collapse = ", ")))
})

# --- Handler: setup_code and suggest_list_name -----------------------------

test_that("suggest_list_name appends trailing underscore", {
  expect_equal(suggest_list_name("es_diff"), "es_diff_")
})

test_that("effectsize handler setup_code is correct", {
  h    <- get_handler("effectsize")
  code <- h$setup_code("es_diff", "es_diff_")
  expect_equal(code, "es_diff_ <- draft::prep_effectsize(es_diff)")
})

test_that("effectsize handler has correct badge", {
  h <- get_handler("effectsize")
  expect_equal(h$badge, "ES")
})

# --- Full inline pipeline --------------------------------------------------

test_that("flat effectsize value resolves in render_inline", {
  result    <- prep_effectsize(es_diff)
  list_name <- suggest_list_name("es_diff")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  first_field <- names(result)[1]
  expected    <- result[[first_field]]
  text <- paste0("Cohen's d: {", list_name, "$", first_field, "}")

  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected), fixed = TRUE)
})

test_that("nested effectsize value resolves in render_inline", {
  result    <- prep_effectsize(es_anova)
  list_name <- suggest_list_name("es_anova")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  first_field <- names(result$cyl)[1]
  expected    <- result$cyl[[first_field]]
  text <- paste0("Eta2 for cyl: {", list_name, "$cyl$", first_field, "}")

  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected), fixed = TRUE)
})

test_that("convert_to_rmd produces correct syntax for flat effectsize path", {
  result    <- prep_effectsize(es_diff)
  list_name <- suggest_list_name("es_diff")
  first_fld <- names(result)[1]

  text       <- paste0("d = {", list_name, "$", first_fld, "}.")
  result_rmd <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result_rmd))
  expect_match(result_rmd, paste0("`r ", list_name, "\\$", first_fld, "`"))
})

test_that("convert_to_rmd produces correct syntax for nested effectsize path", {
  result    <- prep_effectsize(es_anova)
  list_name <- suggest_list_name("es_anova")
  first_fld <- names(result$cyl)[1]

  text       <- paste0("Eta2 = {", list_name, "$cyl$", first_fld, "}.")
  result_rmd <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result_rmd))
  expect_match(result_rmd, paste0("`r ", list_name, "\\$cyl\\$", first_fld, "`"))
})
