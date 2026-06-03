library(testthat)
library(janitor)
library(insight)
library(parameters)

source(test_path("../../R/sanitize.R"))
source(test_path("../../R/model_helpers.R"))
source(test_path("../../R/prep_model.R"))

m_lm  <- lm(mpg ~ wt + cyl, mtcars)
m_glm <- glm(am ~ wt + cyl, mtcars, family = binomial)
m_int <- lm(mpg ~ wt * cyl, mtcars)

test_that("prep_model returns a named list", {
  result <- prep_model(m_lm)
  expect_type(result, "list")
  expect_true(length(result) > 0)
  expect_false(is.null(names(result)))
})

test_that("each parameter sub-list has core fields", {
  result <- prep_model(m_lm)
  for (nm in names(result)) {
    expect_true("estimate" %in% names(result[[nm]]))
    expect_true("ci_low"   %in% names(result[[nm]]))
    expect_true("ci_high"  %in% names(result[[nm]]))
    expect_true("ci"       %in% names(result[[nm]]))
  }
})

test_that("frequentist model has p, not pd", {
  result <- prep_model(m_lm)
  expect_true("p"  %in% names(result$wt))
  expect_false("pd" %in% names(result$wt))
})

test_that("all values are character strings", {
  result <- prep_model(m_lm)
  expect_type(result$wt$estimate, "character")
  expect_type(result$wt$p,        "character")
  expect_type(result$wt$ci,       "character")
})

test_that("interaction terms produce readable keys", {
  result <- prep_model(m_int)
  expect_true("wt_x_cyl" %in% names(result))
})

test_that("glm model works and returns p values", {
  result <- prep_model(m_glm)
  expect_true("wt" %in% names(result))
  expect_true("p"  %in% names(result$wt))
})

test_that("p values use APA format", {
  result <- prep_model(m_lm)
  # wt is highly significant in mpg ~ wt + cyl
  expect_match(result$wt$p, "^p")
})

test_that("unsupported object throws informative error", {
  expect_error(prep_model(list(a = 1)), "Could not extract parameters")
})

test_that("lmer fixed effects work", {
  skip_if_not_installed("lme4")
  library(lme4)
  m_lmer <- lmer(Reaction ~ Days + (Days | Subject), sleepstudy)
  result  <- prep_model(m_lmer, effects = "fixed")
  expect_true("days"      %in% names(result))
  expect_true("intercept" %in% names(result))
  expect_equal(result$days$effects, "fixed")
})

test_that("lmer random effects work", {
  skip_if_not_installed("lme4")
  library(lme4)
  m_lmer <- lmer(Reaction ~ Days + (Days | Subject), sleepstudy)
  result  <- prep_model(m_lmer, effects = "random")
  expect_true("sd_intercept" %in% names(result))
  expect_equal(result$sd_intercept$effects, "random")
  expect_equal(result$sd_intercept$group,   "Subject")
  expect_false("p" %in% names(result$sd_intercept))
})

test_that("lmer all effects returns both fixed and random", {
  skip_if_not_installed("lme4")
  library(lme4)
  m_lmer <- lmer(Reaction ~ Days + (Days | Subject), sleepstudy)
  result  <- prep_model(m_lmer, effects = "all")
  effects_vals <- vapply(result, function(x) if (is.null(x$effects)) NA_character_ else x$effects, character(1))
  expect_true("fixed"  %in% effects_vals)
  expect_true("random" %in% effects_vals)
})
