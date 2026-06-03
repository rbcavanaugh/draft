library(testthat)
library(janitor)

source(test_path("../../R/sanitize.R"))

test_that("sanitize_key handles basic cases", {
  expect_equal(sanitize_key("Age Group"),   "age_group")
  expect_equal(sanitize_key("(Intercept)"), "intercept")
  expect_equal(sanitize_key("my.var"),      "my_var")
})

test_that("sanitize_key converts interaction operators", {
  expect_equal(sanitize_key("wt:cyl"),      "wt_x_cyl")
  expect_equal(sanitize_key("wt*cyl"),      "wt_x_cyl")
  expect_equal(sanitize_key("a : b"),       "a_x_b")
  expect_equal(sanitize_key("a:b:c"),       "a_x_b_x_c")
})

test_that("sanitize_key deduplicates cleanly", {
  result <- sanitize_key(c("age", "age", "age"))
  expect_equal(result, c("age", "age_2", "age_3"))
  expect_equal(length(unique(result)), 3)
})

test_that("sanitize_key handles pre-existing collision", {
  # "age" deduped to "age_2", but "age_2" already exists — must not collide
  result <- sanitize_key(c("age", "age", "age_2"))
  expect_equal(length(unique(result)), 3)
})

test_that("sanitize_key handles empty and NULL input", {
  expect_equal(sanitize_key(character(0)), character(0))
  expect_equal(sanitize_key(NULL),         character(0))
})

test_that("sanitize_key returns same length as input", {
  x <- c("Age Group", "wt:cyl", "(Intercept)", "var.name")
  expect_equal(length(sanitize_key(x)), length(x))
})
