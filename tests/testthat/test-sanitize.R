# test-sanitize.R
#
# Tests for sanitize_key(). The current implementation lowercases, replaces
# spaces with underscores, strips all other non-alphanumeric characters
# (including punctuation and operators), trims leading/trailing underscores,
# and deduplicates with numeric suffixes.

test_that("basic lowercasing and space replacement", {
  expect_equal(sanitize_key("Age Group"),  "age_group")
  expect_equal(sanitize_key("My Var"),     "my_var")
})

test_that("parentheses and punctuation are stripped", {
  expect_equal(sanitize_key("(Intercept)"), "intercept")
  expect_equal(sanitize_key("my.var"),      "myvar")
  expect_equal(sanitize_key("a-b"),         "ab")
})

test_that("colon operators (interaction terms) are stripped", {
  # The current implementation removes ':' — no '_x_' conversion
  expect_equal(sanitize_key("wt:cyl"),  "wtcyl")
  expect_equal(sanitize_key("a:b:c"),   "abc")
})

test_that("leading and trailing underscores are removed", {
  expect_equal(sanitize_key("_leading"), "leading")
  expect_equal(sanitize_key("trailing_"), "trailing")
})

test_that("result contains only lowercase alphanumeric and underscores", {
  inputs <- c("Age Group", "(Intercept)", "wt:cyl", "my.var", "Factor1")
  results <- sanitize_key(inputs)
  expect_true(all(grepl("^[a-z0-9_]+$", results)))
})

test_that("deduplication appends _2, _3 for repeated names", {
  result <- sanitize_key(c("age", "age", "age"))
  expect_equal(result, c("age", "age_2", "age_3"))
  expect_equal(length(unique(result)), 3)
})

test_that("deduplication handles pre-existing collision", {
  result <- sanitize_key(c("age", "age", "age_2"))
  expect_equal(length(unique(result)), 3)
})

test_that("handles empty and NULL input", {
  expect_equal(sanitize_key(character(0)), character(0))
  expect_equal(sanitize_key(NULL),         character(0))
})

test_that("returns same length as input", {
  x <- c("Age Group", "wt:cyl", "(Intercept)", "var.name")
  expect_equal(length(sanitize_key(x)), length(x))
})

test_that("result is always unnamed", {
  result <- sanitize_key(c(a = "Age Group", b = "wt"))
  expect_null(names(result))
})
