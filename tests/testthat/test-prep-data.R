# test-prep-data.R
#
# Retained for reference; comprehensive tests for prep_data() now live in
# test-class-dataframe.R which also covers the full inline pipeline.

test_that("prep_data rejects non-data-frames", {
  expect_error(prep_data(list(a = 1)), "data frame")
  expect_error(prep_data("text"),      "data frame")
})

test_that("prep_data returns named list with one entry per column", {
  result <- prep_data(mtcars)
  expect_type(result, "list")
  expect_equal(length(result), ncol(mtcars))
})

test_that("continuous column has expected sub-fields", {
  result <- prep_data(data.frame(x = 1:20))
  expect_named(result$x, c("mean", "sd", "median", "min", "max", "n", "n_missing"))
})

test_that("NAs are reported correctly", {
  result <- prep_data(data.frame(x = c(1:15, NA, NA)))
  expect_equal(result$x$n_missing, "2")
  expect_equal(result$x$n,         "15")
})

test_that("factor column is treated as categorical", {
  df     <- data.frame(sex = factor(c("male", "female", "female", "male", "female")))
  result <- prep_data(df)
  expect_true("female" %in% names(result$sex))
  expect_equal(result$sex$female$n, "3")
})

test_that("zero-row data frame does not crash", {
  expect_no_error(prep_data(mtcars[0, ]))
})
