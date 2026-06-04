# test-class-datawizard.R
#
# Full pipeline tests for the datawizard handler:
#   classify_object -> prep_distribution -> suggest_list_name -> setup_code
#   -> assign to render_env -> render_inline -> convert_to_rmd
#
# Objects tested:
#   describe_distribution(iris)              — no stratification (flat)
#   describe_distribution(iris, by="Species") — stratified by group
#
# All tests skip if datawizard is not installed.

skip_if_not_installed("datawizard")
library(datawizard)

# --- Shared fixtures -------------------------------------------------------

dist_flat  <- describe_distribution(iris[, 1:4])
dist_strat <- describe_distribution(iris, by = "Species")

# --- Classification --------------------------------------------------------

test_that("classify_object returns 'datawizard' for describe_distribution output", {
  expect_equal(classify_object(dist_flat),  "datawizard")
  expect_equal(classify_object(dist_strat), "datawizard")
})

test_that("datawizard objects are not mis-classified as dataframe", {
  expect_false(classify_object(dist_flat) == "dataframe")
})

# --- prep_distribution: flat (no by) --------------------------------------

test_that("prep_distribution returns a named list for flat input", {
  result <- prep_distribution(dist_flat)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  expect_false(is.null(names(result)))
})

test_that("flat result has one entry per variable", {
  result <- prep_distribution(dist_flat)
  expect_equal(length(result), 4)  # iris has 4 numeric columns
})

test_that("flat result keys match variable names", {
  result <- prep_distribution(dist_flat)
  # sanitize_key strips dots: "Sepal.Length" -> "sepallength"
  expect_true("sepallength" %in% names(result))
  expect_true("sepalwidth"  %in% names(result))
  expect_true("petallength" %in% names(result))
  expect_true("petalwidth"  %in% names(result))
})

test_that("flat result entries are named lists of character strings", {
  result <- prep_distribution(dist_flat)
  for (nm in names(result)) {
    expect_type(result[[nm]], "list")
    for (field in names(result[[nm]])) {
      expect_type(result[[nm]][[field]], "character")
    }
  }
})

test_that("flat result includes mean and sd fields", {
  result <- prep_distribution(dist_flat)
  expect_true("mean" %in% names(result$sepallength))
  expect_true("sd"   %in% names(result$sepallength))
})

# --- prep_distribution: stratified (with by) ------------------------------

test_that("prep_distribution returns nested list for stratified input", {
  result <- prep_distribution(dist_strat)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  # top-level entries are groups, second-level are variables
  expect_type(result[[1]], "list")
  expect_type(result[[1]][[1]], "list")
})

test_that("stratified result has one top-level entry per Species", {
  result <- prep_distribution(dist_strat)
  expect_equal(length(result), 3)
  expect_true("setosa"     %in% names(result))
  expect_true("versicolor" %in% names(result))
  expect_true("virginica"  %in% names(result))
})

test_that("stratified result second-level keys are variable names", {
  result <- prep_distribution(dist_strat)
  expect_true("sepallength" %in% names(result$setosa))
  expect_true("petallength" %in% names(result$setosa))
})

test_that("stratified result leaf entries are named lists of character strings", {
  result <- prep_distribution(dist_strat)
  for (grp in names(result)) {
    for (var in names(result[[grp]])) {
      expect_type(result[[grp]][[var]], "list")
      for (field in names(result[[grp]][[var]])) {
        expect_type(result[[grp]][[var]][[field]], "character")
      }
    }
  }
})

test_that("stratified result includes mean field at leaf level", {
  result <- prep_distribution(dist_strat)
  expect_true("mean" %in% names(result$setosa$sepallength))
})

# --- Formatting: decimal places --------------------------------------------

test_that("prep_distribution values never exceed 2 decimal places", {
  result <- prep_distribution(dist_flat)
  values <- unlist(result)
  values <- values[!grepl("^[<>]", trimws(values))]
  bad    <- values[grepl("\\.[0-9]*[1-9][0-9]{2,}", values)]
  expect_equal(length(bad), 0L,
               info = paste("Over-precise values:", paste(bad, collapse = ", ")))
})

# --- Handler: setup_code, badge, suggest_list_name ------------------------

test_that("suggest_list_name appends trailing underscore", {
  expect_equal(suggest_list_name("dist"), "dist_")
})

test_that("datawizard handler setup_code is correct", {
  h    <- get_handler("datawizard")
  code <- h$setup_code("dist_flat", "dist_flat_")
  expect_equal(code, "dist_flat_ <- draft::prep_distribution(dist_flat)")
})

test_that("datawizard handler has correct badge", {
  h <- get_handler("datawizard")
  expect_equal(h$badge, "DW")
})

# --- Full inline pipeline --------------------------------------------------

test_that("flat distribution value resolves in render_inline", {
  result    <- prep_distribution(dist_flat)
  list_name <- suggest_list_name("dist_flat")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  expected <- result$sepallength$mean
  text <- paste0("Mean sepal length: {", list_name, "$sepallength$mean}")

  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected), fixed = TRUE)
})

test_that("stratified distribution value resolves in render_inline", {
  result    <- prep_distribution(dist_strat)
  list_name <- suggest_list_name("dist_strat")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  expected <- result$setosa$sepallength$mean
  text <- paste0("Setosa mean: {", list_name, "$setosa$sepallength$mean}")

  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected), fixed = TRUE)
})

test_that("convert_to_rmd produces correct syntax for flat distribution path", {
  result    <- prep_distribution(dist_flat)
  list_name <- suggest_list_name("dist_flat")

  text       <- paste0("M = {", list_name, "$sepallength$mean}.")
  result_rmd <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result_rmd))
  expect_match(result_rmd, paste0("`r ", list_name, "\\$sepallength\\$mean`"))
})

test_that("convert_to_rmd produces correct syntax for stratified path", {
  result    <- prep_distribution(dist_strat)
  list_name <- suggest_list_name("dist_strat")

  text       <- paste0("M = {", list_name, "$setosa$sepallength$mean}.")
  result_rmd <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result_rmd))
  expect_match(result_rmd, paste0("`r ", list_name, "\\$setosa\\$sepallength\\$mean`"))
})
