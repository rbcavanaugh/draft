library(testthat)
library(janitor)
library(insight)

source(test_path("../../R/sanitize.R"))
source(test_path("../../R/prep_data.R"))

test_that("prep_data rejects non-data-frames", {
  expect_error(prep_data(list(a = 1)), "`df` must be a data frame")
  expect_error(prep_data("text"),      "`df` must be a data frame")
})

test_that("prep_data returns named list with one entry per column", {
  result <- prep_data(mtcars)
  expect_type(result, "list")
  expect_equal(length(result), ncol(mtcars))
})

test_that("continuous column has expected sub-fields", {
  result <- prep_data(data.frame(x = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)))
  expect_named(result$x, c("mean", "sd", "median", "min", "max", "n", "n_missing"))
  expect_type(result$x$mean, "character")
  expect_equal(result$x$n, "11")
  expect_equal(result$x$n_missing, "0")
})

test_that("continuous column with NAs reports n_missing correctly", {
  result <- prep_data(data.frame(x = c(1:15, NA, NA)))
  expect_equal(result$x$n_missing, "2")
  expect_equal(result$x$n, "15")
})

test_that("all-NA column does not crash and reports n_missing", {
  # An all-NA numeric column has 0 unique values, so it falls into the
  # categorical path (0 <= cat_threshold). Result has n and n_missing but
  # no level sub-lists. The important thing is it doesn't error.
  result <- prep_data(data.frame(x = rep(NA_real_, 5)))
  expect_no_error(prep_data(data.frame(x = rep(NA_real_, 5))))
  expect_equal(result$x$n, "0")
  expect_equal(result$x$n_missing, "5")
})

test_that("single-value continuous column returns NA for sd", {
  result <- prep_data(data.frame(x = c(rep(1:15, 1), 1)))  # >10 unique, continuous
  expect_type(result$x$sd, "character")
})

test_that("factor column is treated as categorical", {
  df     <- data.frame(sex = factor(c("male", "female", "female", "male", "female")))
  result <- prep_data(df)
  expect_true("female" %in% names(result$sex))
  expect_true("male"   %in% names(result$sex))
  expect_equal(result$sex$female$n, "3")
  expect_equal(result$sex$female$pct, "60")
})

test_that("categorical column includes n and n_missing at top level", {
  df     <- data.frame(site = c("A", "B", "A", NA))
  result <- prep_data(df)
  expect_equal(result$site$n, "3")
  expect_equal(result$site$n_missing, "1")
})

test_that("all-NA categorical column returns n=0 without crashing", {
  df     <- data.frame(x = factor(rep(NA, 4)))
  result <- prep_data(df)
  expect_equal(result$x$n, "0")
  expect_equal(result$x$n_missing, "4")
})

test_that("cat_threshold controls continuous vs categorical detection", {
  # default threshold = 10: 5 unique values -> categorical
  df <- data.frame(score = c(1, 2, 3, 4, 5, 1, 2, 3))
  expect_true("x1" %in% names(prep_data(df)$score))  # categorical level

  # raised threshold: still categorical but all numeric treated as continuous
  result_cont <- prep_data(df, cat_threshold = 2)
  expect_named(result_cont$score, c("mean", "sd", "median", "min", "max", "n", "n_missing"))
})

test_that("zero-row data frame does not crash", {
  df <- mtcars[0, ]
  expect_no_error(prep_data(df))
})

test_that("logical NAs are not counted as a category level", {
  # Before the fix, as.character(NA) == "NA" would pass the !is.na() filter
  # and be counted as a level named "NA".
  df     <- data.frame(flag = c(TRUE, FALSE, NA, TRUE))
  result <- prep_data(df)
  level_names <- setdiff(names(result$flag), c("n", "n_missing"))
  expect_false("NA" %in% level_names)
  expect_equal(result$flag$n, "3")
  expect_equal(result$flag$n_missing, "1")
})
