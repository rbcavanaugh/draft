# test-code-generator.R
#
# Tests for suggest_list_name() and handler setup_code functions.
# Full pipeline coverage is in the per-class test files.

test_that("suggest_list_name appends trailing underscore", {
  expect_equal(suggest_list_name("m1"),        "m1_")
  expect_equal(suggest_list_name("model_age"), "model_age_")
  expect_equal(suggest_list_name("demo_data"), "demo_data_")
  expect_equal(suggest_list_name("perf"),      "perf_")
})

test_that("suggest_list_name works with any string", {
  expect_equal(suggest_list_name("x"), "x_")
})

test_that("parameters_model handler setup_code format", {
  h <- get_handler("parameters_model")
  expect_equal(
    h$setup_code("params_m1", "params_m1_"),
    "params_m1_ <- draft::prep_params(params_m1)"
  )
})

test_that("dataframe handler setup_code format", {
  h <- get_handler("dataframe")
  expect_equal(
    h$setup_code("my_data", "my_data_"),
    "my_data_ <- draft::prep_data(my_data)"
  )
})

test_that("modelbased handler setup_code format", {
  h <- get_handler("modelbased")
  expect_equal(
    h$setup_code("my_means", "my_means_"),
    "my_means_ <- draft::prep_modelbased(my_means)"
  )
})

test_that("performance handler setup_code format", {
  h <- get_handler("performance")
  expect_equal(
    h$setup_code("perf_m1", "perf_m1_"),
    "perf_m1_ <- draft::prep_performance(perf_m1)"
  )
})
