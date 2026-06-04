# test-prep-model.R
#
# Retained for reference; comprehensive tests for prep_params() now live in
# test-class-parameters.R which also covers the full inline pipeline.

library(parameters)

m_lm  <- lm(mpg ~ wt + cyl, data = mtcars)
m_glm <- glm(am ~ wt + cyl, data = mtcars, family = binomial)
m_int <- lm(mpg ~ wt * cyl, data = mtcars)

test_that("prep_params returns a named list", {
  result <- prep_params(model_parameters(m_lm))
  expect_type(result, "list")
  expect_gt(length(result), 0)
})

test_that("each parameter sub-list has coefficient and p", {
  result <- prep_params(model_parameters(m_lm))
  expect_true("coefficient" %in% names(result$wt))
  expect_true("p"           %in% names(result$wt))
})

test_that("all values are character strings", {
  result <- prep_params(model_parameters(m_lm))
  expect_type(result$wt$coefficient, "character")
  expect_type(result$wt$p,           "character")
})

test_that("glm model works", {
  result <- prep_params(model_parameters(m_glm))
  expect_true("wt" %in% names(result))
})

test_that("lmer fixed effects work", {
  skip_if_not_installed("lme4")
  m_lmer <- lme4::lmer(Reaction ~ Days + (Days | Subject), data = lme4::sleepstudy)
  result  <- prep_params(model_parameters(m_lmer, effects = "fixed"))
  expect_true("days" %in% names(result))
})
