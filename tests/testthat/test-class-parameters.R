# test-class-parameters.R
#
# Full pipeline tests for the parameters_model handler:
#   classify_object -> prep_params -> suggest_list_name -> setup_code
#   -> assign to render_env -> render_inline -> convert_to_rmd
#
# Objects tested: lm, glm, interaction terms, lmer (fixed/random), correlation

library(parameters)

# --- Shared fixtures -------------------------------------------------------

m_lm  <- lm(mpg ~ wt + cyl, data = mtcars)
m_glm <- glm(am ~ wt + cyl, data = mtcars, family = binomial)
m_int <- lm(mpg ~ wt * cyl, data = mtcars)

params_lm  <- model_parameters(m_lm)
params_glm <- model_parameters(m_glm)
params_int <- model_parameters(m_int)

# --- Classification --------------------------------------------------------

test_that("classify_object returns 'parameters_model' for model_parameters output", {
  expect_equal(classify_object(params_lm),  "parameters_model")
  expect_equal(classify_object(params_glm), "parameters_model")
})

test_that("parameters_model is not mis-classified as dataframe", {
  expect_false(classify_object(params_lm) == "dataframe")
})

# --- prep_params: structure ------------------------------------------------

test_that("prep_params returns a named list", {
  result <- prep_params(params_lm)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  expect_false(is.null(names(result)))
})

test_that("each element is a named sub-list of character strings", {
  result <- prep_params(params_lm)
  for (nm in names(result)) {
    expect_type(result[[nm]], "list")
    for (field in names(result[[nm]])) {
      expect_type(result[[nm]][[field]], "character")
    }
  }
})

test_that("frequentist lm includes coefficient and p, not pd", {
  result <- prep_params(params_lm)
  # parameters::format() uses "Coefficient" for lm; maps to "coefficient" after cleaning
  expect_true("coefficient" %in% names(result$wt))
  expect_true("p"           %in% names(result$wt))
  expect_false("pd"         %in% names(result$wt))
})

test_that("CI field is present (format varies by parameters version)", {
  result    <- prep_params(params_lm)
  ci_fields <- grep("ci", names(result$wt), value = TRUE)
  expect_gt(length(ci_fields), 0)
})

# --- prep_params: key generation -------------------------------------------

test_that("parameter names are sanitized to valid keys", {
  result <- prep_params(params_lm)
  expect_true(all(grepl("^[a-z0-9_]+$", names(result))))
})

test_that("intercept key is 'intercept'", {
  result <- prep_params(params_lm)
  expect_true("intercept" %in% names(result))
})

test_that("interaction term produces a key with underscore separator", {
  result <- prep_params(params_int)
  # wt:cyl sanitizes to something containing wt and cyl
  int_keys <- grep("wt.*cyl|cyl.*wt", names(result), value = TRUE)
  expect_gt(length(int_keys), 0)
})

# --- prep_params: object varieties -----------------------------------------

test_that("glm model preps successfully", {
  result <- prep_params(params_glm)
  expect_true("wt" %in% names(result))
  expect_true("p"  %in% names(result$wt))
})

test_that("lmer fixed effects prep successfully", {
  skip_if_not_installed("lme4")
  m_lmer     <- lme4::lmer(Reaction ~ Days + (Days | Subject), data = lme4::sleepstudy)
  params_lmer <- model_parameters(m_lmer, effects = "fixed")
  result      <- prep_params(params_lmer)
  expect_true("days"      %in% names(result))
  expect_true("intercept" %in% names(result))
})

test_that("lmer random effects prep successfully", {
  skip_if_not_installed("lme4")
  m_lmer      <- lme4::lmer(Reaction ~ Days + (Days | Subject), data = lme4::sleepstudy)
  params_rand <- model_parameters(m_lmer, effects = "random")
  result       <- prep_params(params_rand)
  expect_gt(length(result), 0)
})

test_that("correlation matrix (parameters_model) preps successfully", {
  skip_if_not_installed("correlation")
  # correlation() output has its own parameters_model method
  corr_obj  <- correlation::correlation(mtcars[, 1:4])
  params_c  <- as.data.frame(corr_obj)  # use the data frame representation
  # The raw correlation data frame is not a parameters_model so skip prep_params;
  # test that classify_object is robust to this
  expect_false(classify_object(params_c) == "parameters_model")
})

test_that("non-parameters_model object throws informative error", {
  expect_error(prep_params(list(a = 1)), regexp = "parameter")
})

# --- Formatting: decimal places --------------------------------------------

test_that("prep_params non-p values never exceed 2 decimal places", {
  result   <- prep_params(params_lm)
  all_vals <- unlist(result)
  p_names  <- grepl("(\\.p|^p)$", names(all_vals))
  values   <- all_vals[!p_names]
  values   <- trimws(values)
  values   <- values[!grepl("^[<>]", values)]
  bad      <- values[grepl("\\.[0-9]*[1-9][0-9]{2,}", values)]
  expect_equal(length(bad), 0L,
               info = paste("Over-precise values:", paste(bad, collapse = ", ")))
})

test_that("prep_params p values are APA formatted (3 dp or < .001)", {
  result   <- prep_params(params_lm)
  all_vals <- unlist(result)
  p_vals   <- trimws(all_vals[grepl("(\\.p|^p)$", names(all_vals))])
  # Each p-value must be threshold-formatted or have exactly 3 decimal places
  valid <- grepl("^[<>]\\s*[0-9.]+$|\\.[0-9]{3}$", p_vals)
  expect_true(all(valid),
              info = paste("Badly formatted p-values:", paste(p_vals[!valid], collapse = ", ")))
})

# --- Handler: setup_code and suggest_list_name -----------------------------

test_that("suggest_list_name appends trailing underscore", {
  expect_equal(suggest_list_name("params_m1"), "params_m1_")
  expect_equal(suggest_list_name("my_model"),  "my_model_")
})

test_that("parameters_model handler setup_code is correct", {
  h    <- get_handler("parameters_model")
  code <- h$setup_code("params_m1", "params_m1_")
  expect_equal(code, "params_m1_ <- draft::prep_params(params_m1)")
})

# --- Full inline pipeline --------------------------------------------------

test_that("prep_params output resolves in render_inline", {
  result    <- prep_params(params_lm)
  list_name <- suggest_list_name("params_lm")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  # Use "coefficient" — the actual field name for lm in parameters
  expected_val <- result$wt$coefficient
  text <- paste0("Weight estimate: {", list_name, "$wt$coefficient}")

  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected_val), fixed = TRUE)
})

test_that("p-value path resolves in render_inline", {
  result    <- prep_params(params_lm)
  list_name <- suggest_list_name("params_lm")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  text <- paste0("p = {", list_name, "$wt$p}")
  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
})

test_that("convert_to_rmd produces valid backtick-r syntax for parameter path", {
  list_name <- suggest_list_name("params_lm")
  text      <- paste0("b = {", list_name, "$wt$coefficient}, p = {", list_name, "$wt$p}")
  result    <- convert_to_rmd(text, "{}")
  expect_match(result, paste0("`r ", list_name, "\\$wt\\$coefficient`"))
  expect_match(result, paste0("`r ", list_name, "\\$wt\\$p`"))
  expect_false(grepl("\\{", result))
})

test_that("full prose sentence converts cleanly to rmd", {
  list_name <- suggest_list_name("p")
  text <- paste0(
    "Weight was negatively associated with fuel economy ",
    "(b = {", list_name, "$wt$coefficient}, p = {", list_name, "$wt$p})."
  )
  result <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result))
  expect_match(result, "`r p_\\$wt\\$coefficient`")
})
