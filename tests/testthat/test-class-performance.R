# test-class-performance.R
#
# Full pipeline tests for the performance handler:
#   classify_object -> prep_performance -> suggest_list_name -> setup_code
#   -> assign to render_env -> render_inline -> convert_to_rmd
#
# Objects tested: model_performance (lm, glm, lmer), compare_performance
# All tests skip if performance is not installed.

skip_if_not_installed("performance")
library(performance)

# --- Shared fixtures -------------------------------------------------------

m_lm   <- lm(mpg ~ wt + cyl, data = mtcars)
m_lm2  <- lm(mpg ~ wt,       data = mtcars)
m_glm  <- glm(am ~ wt + cyl, data = mtcars, family = binomial)

perf_lm    <- model_performance(m_lm)
perf_glm   <- model_performance(m_glm)
comp_perf  <- compare_performance(m_lm, m_lm2)

# --- Classification --------------------------------------------------------

test_that("classify_object returns 'performance' for model_performance output", {
  expect_equal(classify_object(perf_lm),  "performance")
  expect_equal(classify_object(perf_glm), "performance")
})

test_that("classify_object returns 'performance' for compare_performance output", {
  expect_equal(classify_object(comp_perf), "performance")
})

test_that("performance objects are not mis-classified as dataframe", {
  expect_false(classify_object(perf_lm) == "dataframe")
})

# --- prep_performance: model_performance -----------------------------------

test_that("prep_performance(model_performance) returns a flat named list", {
  result <- prep_performance(perf_lm)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  # flat: no sub-lists (values are character strings directly)
  expect_true(all(vapply(result, is.character, logical(1))))
})

test_that("model_performance list has no nested sub-lists", {
  result <- prep_performance(perf_lm)
  nested <- vapply(result, is.list, logical(1))
  expect_false(any(nested))
})

test_that("all values in model_performance list are character strings", {
  result <- prep_performance(perf_lm)
  for (nm in names(result)) {
    expect_type(result[[nm]], "character")
  }
})

test_that("model_performance includes common lm metrics", {
  result <- prep_performance(perf_lm)
  # lm should include r2 and something about RMSE or sigma
  expect_true(any(grepl("r2|r2_adjusted", names(result), ignore.case = TRUE)))
})

test_that("glm model_performance preps without error", {
  result <- prep_performance(perf_glm)
  expect_type(result, "list")
  expect_gt(length(result), 0)
})

test_that("lmer model_performance preps without error", {
  skip_if_not_installed("lme4")
  m_lmer   <- lme4::lmer(Reaction ~ Days + (Days | Subject), data = lme4::sleepstudy)
  perf_lmer <- model_performance(m_lmer)
  result   <- prep_performance(perf_lmer)
  expect_type(result, "list")
  expect_gt(length(result), 0)
})

# --- prep_performance: compare_performance ---------------------------------

test_that("prep_performance(compare_performance) returns a nested named list", {
  result <- prep_performance(comp_perf)
  expect_type(result, "list")
  expect_equal(length(result), 2)
  # nested: each element is a sub-list
  expect_true(all(vapply(result, is.list, logical(1))))
})

test_that("compare_performance keys match model names", {
  result    <- prep_performance(comp_perf)
  key_names <- names(result)
  # Keys are sanitized model names — both should be non-empty
  expect_equal(length(key_names), 2)
  expect_true(all(nchar(key_names) > 0))
})

test_that("each model entry in compare_performance has character metric values", {
  result <- prep_performance(comp_perf)
  for (model_key in names(result)) {
    for (metric in names(result[[model_key]])) {
      expect_type(result[[model_key]][[metric]], "character")
    }
  }
})

test_that("compare_performance entries share the same metric names", {
  result   <- prep_performance(comp_perf)
  metrics1 <- names(result[[1]])
  metrics2 <- names(result[[2]])
  expect_equal(metrics1, metrics2)
})

# --- Formatting: decimal places --------------------------------------------

test_that("prep_performance values never exceed 2 decimal places", {
  m      <- lm(mpg ~ wt + cyl, data = mtcars)
  perf   <- performance::model_performance(m)
  result <- prep_performance(perf)
  values <- unlist(result)
  values <- values[!grepl("^[<>]", trimws(values))]
  bad    <- values[grepl("\\.[0-9]*[1-9][0-9]{2,}", values)]
  expect_equal(length(bad), 0L,
               info = paste("Over-precise values:", paste(bad, collapse = ", ")))
})

# --- Handler: setup_code, suggest_list_name, badges -----------------------

test_that("suggest_list_name appends trailing underscore", {
  expect_equal(suggest_list_name("perf_m1"), "perf_m1_")
})

test_that("performance handler setup_code is correct", {
  h    <- get_handler("performance")
  code <- h$setup_code("perf_m1", "perf_m1_")
  expect_equal(code, "perf_m1_ <- draft::prep_performance(perf_m1)")
})

test_that("performance handler has correct badge", {
  h <- get_handler("performance")
  expect_equal(h$badge, "PF")
})

# --- Full inline pipeline: model_performance (flat) -----------------------

test_that("model_performance metric resolves in render_inline", {
  result    <- prep_performance(perf_lm)
  list_name <- suggest_list_name("perf_lm")
  first_key <- names(result)[1]
  first_val <- result[[first_key]]

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  text <- paste0("R2 = {", list_name, "$", first_key, "}")
  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(first_val), fixed = TRUE)
})

test_that("convert_to_rmd for model_performance path produces valid rmd", {
  result    <- prep_performance(perf_lm)
  list_name <- suggest_list_name("perf_lm")
  first_key <- names(result)[1]

  text   <- paste0("R2 = {", list_name, "$", first_key, "}.")
  result_rmd <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result_rmd))
  expect_match(result_rmd, paste0("`r ", list_name, "\\$", first_key, "`"))
})

# --- Full inline pipeline: compare_performance (nested) -------------------

test_that("compare_performance nested path resolves in render_inline", {
  result    <- prep_performance(comp_perf)
  list_name <- suggest_list_name("comp")
  model_key <- names(result)[1]
  metric    <- names(result[[model_key]])[1]
  expected  <- result[[model_key]][[metric]]

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  text <- paste0("AIC = {", list_name, "$", model_key, "$", metric, "}")
  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected), fixed = TRUE)
})

test_that("convert_to_rmd for compare_performance path produces valid rmd", {
  result    <- prep_performance(comp_perf)
  list_name <- suggest_list_name("comp")
  model_key <- names(result)[1]
  metric    <- names(result[[model_key]])[1]

  text       <- paste0("Model 1 AIC: {", list_name, "$", model_key, "$", metric, "}")
  result_rmd <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result_rmd))
  expect_match(result_rmd, "`r ")
})
