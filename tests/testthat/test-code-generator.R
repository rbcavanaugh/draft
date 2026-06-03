library(testthat)

source(test_path("../../R/code_generator.R"))

test_that("suggest_list_name uses results_ prefix for models", {
  expect_equal(suggest_list_name("m1",        "model"), "results_m1")
  expect_equal(suggest_list_name("model_age", "model"), "results_model_age")
})

test_that("suggest_list_name uses stats_ prefix for dataframes", {
  expect_equal(suggest_list_name("mydata", "dataframe"), "stats_mydata")
  expect_equal(suggest_list_name("demo",   "dataframe"), "stats_demo")
})

test_that("suggest_list_name defaults to model prefix when type omitted", {
  expect_equal(suggest_list_name("m1"), "results_m1")
})

test_that("generate_setup_code omits effects arg when fixed (default)", {
  code <- generate_setup_code("m1", "results_m1", "fixed")
  expect_equal(code, "results_m1 <- draft::prep_model(m1)")
  expect_false(grepl("effects", code))
})

test_that("generate_setup_code includes effects arg for non-fixed", {
  code <- generate_setup_code("m1", "results_m1", "all")
  expect_true(grepl('effects = "all"', code, fixed = TRUE))
})

test_that("generate_data_setup_code produces correct one-liner", {
  code <- generate_data_setup_code("mydata", "stats_mydata")
  expect_equal(code, "stats_mydata <- draft::prep_data(mydata)")
})
