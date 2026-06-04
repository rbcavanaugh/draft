# test-class-dataframe.R
#
# Full pipeline tests for the dataframe handler:
#   classify_object -> prep_data -> suggest_list_name -> setup_code
#   -> assign to render_env -> render_inline -> convert_to_rmd
#
# Also covers raw_columns() (raw mode) and the handler's context/assign_result.
#
# Objects tested: continuous, categorical, mixed, NAs, tibble, zero-row

# --- Classification --------------------------------------------------------

test_that("classify_object returns 'dataframe' for a plain data frame", {
  expect_equal(classify_object(mtcars), "dataframe")
  expect_equal(classify_object(iris),   "dataframe")
})

test_that("classify_object returns 'dataframe' for a tibble", {
  skip_if_not_installed("tibble")
  tb <- tibble::as_tibble(mtcars)
  expect_equal(classify_object(tb), "dataframe")
})

test_that("parameters_model is not mis-classified as dataframe", {
  params <- parameters::model_parameters(lm(mpg ~ wt, mtcars))
  expect_false(classify_object(params) == "dataframe")
})

# --- prep_data: continuous columns -----------------------------------------

test_that("prep_data returns a named list with one entry per column", {
  result <- prep_data(mtcars)
  expect_type(result, "list")
  expect_equal(length(result), ncol(mtcars))
  expect_equal(names(result), sanitize_key(names(mtcars)))
})

test_that("continuous column has all expected sub-fields", {
  df     <- data.frame(x = 1:20)
  result <- prep_data(df)
  expect_named(result$x, c("mean", "sd", "median", "min", "max", "n", "n_missing"))
})

test_that("continuous column values are character strings", {
  result <- prep_data(mtcars)
  expect_type(result$mpg$mean,   "character")
  expect_type(result$mpg$sd,     "character")
  expect_type(result$mpg$median, "character")
  expect_type(result$mpg$n,      "character")
})

test_that("n and n_missing are correct for complete data", {
  df     <- data.frame(x = 1:10)
  result <- prep_data(df)
  expect_equal(result$x$n,         "10")
  expect_equal(result$x$n_missing, "0")
})

test_that("n_missing counts NA values correctly", {
  df     <- data.frame(x = c(1:8, NA, NA))
  result <- prep_data(df)
  expect_equal(result$x$n,         "8")
  expect_equal(result$x$n_missing, "2")
})

# --- prep_data: categorical columns ----------------------------------------

test_that("factor column is treated as categorical", {
  df     <- data.frame(sex = factor(c("male", "female", "female", "male", "female")))
  result <- prep_data(df)
  expect_true("female" %in% names(result$sex))
  expect_true("male"   %in% names(result$sex))
  expect_equal(result$sex$female$n,   "3")
  expect_equal(result$sex$female$pct, "60")
})

test_that("character column is treated as categorical", {
  df     <- data.frame(grp = c("A", "B", "A", "A"), stringsAsFactors = FALSE)
  result <- prep_data(df)
  # Level names come from table() and preserve original case
  expect_true("A" %in% names(result$grp))
  expect_equal(result$grp$A$n, "3")
})

test_that("categorical column has n and n_missing at top level", {
  df     <- data.frame(grp = c("A", "B", "A", NA), stringsAsFactors = FALSE)
  result <- prep_data(df)
  expect_equal(result$grp$n,         "3")
  expect_equal(result$grp$n_missing, "1")
})

test_that("numeric column with few unique values is treated as categorical", {
  df     <- data.frame(cyl = c(4, 4, 6, 8, 6, 4))  # 3 unique values <= threshold 10
  result <- prep_data(df)
  # Level names come from table(); numeric levels produce keys like "4", "6", "8"
  level_keys <- setdiff(names(result$cyl), c("n", "n_missing"))
  expect_gt(length(level_keys), 0)
  expect_true("4" %in% level_keys)
})

test_that("cat_threshold controls continuous vs categorical boundary", {
  df      <- data.frame(score = as.numeric(1:5))  # 5 unique values
  summary <- prep_data(df, cat_threshold = 3)     # 5 > 3 -> continuous
  categorical <- prep_data(df, cat_threshold = 10) # 5 <= 10 -> categorical
  expect_true("mean" %in% names(summary$score))
  expect_false("mean" %in% names(categorical$score))
})

# --- prep_data: edge cases -------------------------------------------------

test_that("zero-row data frame does not error", {
  expect_no_error(prep_data(mtcars[0, ]))
})

test_that("all-NA numeric column does not error", {
  df <- data.frame(x = rep(NA_real_, 5))
  expect_no_error(prep_data(df))
  result <- prep_data(df)
  expect_equal(result$x$n_missing, "5")
})

test_that("single-column data frame works", {
  df     <- data.frame(age = c(25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75))
  result <- prep_data(df)
  expect_equal(length(result), 1)
  expect_true("mean" %in% names(result$age))
})

test_that("tibble is handled identically to data frame", {
  skip_if_not_installed("tibble")
  tb     <- tibble::as_tibble(iris)
  result <- prep_data(tb)
  expect_equal(length(result), ncol(iris))
})

test_that("prep_data rejects non-data-frames", {
  expect_error(prep_data(list(a = 1, b = 2)), "data frame")
  expect_error(prep_data("text"),             "data frame")
})

# --- Formatting: decimal places --------------------------------------------

test_that("prep_data values never exceed 2 decimal places", {
  result <- prep_data(mtcars[, c("mpg", "wt", "cyl")])
  values <- unlist(result)
  values <- values[!grepl("^[<>]", trimws(values))]
  bad    <- values[grepl("\\.[0-9]*[1-9][0-9]{2,}", values)]
  expect_equal(length(bad), 0L,
               info = paste("Over-precise values:", paste(bad, collapse = ", ")))
})

# --- Handler: setup_code, suggest_list_name, assign_result -----------------

test_that("suggest_list_name appends trailing underscore", {
  expect_equal(suggest_list_name("demo_data"), "demo_data_")
})

test_that("dataframe handler setup_code is correct", {
  h    <- get_handler("dataframe")
  code <- h$setup_code("demo_data", "demo_data_")
  expect_equal(code, "demo_data_ <- draft::prep_data(demo_data)")
})

test_that("dataframe handler assign_result returns only the summary sub-list", {
  h      <- get_handler("dataframe")
  result <- list(mode = "summary", summary = list(x = list(mean = "1.0")), obj = data.frame())
  val    <- h$assign_result(result)
  expect_equal(val, list(x = list(mean = "1.0")))
  expect_null(val$mode)
})

# --- Full inline pipeline --------------------------------------------------

test_that("continuous column mean resolves in render_inline", {
  df        <- data.frame(age = c(25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75))
  result    <- prep_data(df)
  list_name <- suggest_list_name("demo")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  expected <- result$age$mean
  text <- paste0("Mean age: {", list_name, "$age$mean}")
  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected), fixed = TRUE)
})

test_that("categorical level pct resolves in render_inline", {
  df        <- data.frame(sex = factor(c("male", "female", "female", "male", "female")))
  result    <- prep_data(df)
  list_name <- suggest_list_name("demo")

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  text <- paste0("{", list_name, "$sex$female$pct}% were female")
  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, "60")
})

test_that("convert_to_rmd produces correct syntax for data paths", {
  list_name <- suggest_list_name("demo_data")
  text      <- paste0(
    "M = {", list_name, "$age$mean} (SD = {", list_name, "$age$sd})"
  )
  result <- convert_to_rmd(text, "{}")
  expect_match(result, paste0("`r ", list_name, "\\$age\\$mean`"))
  expect_match(result, paste0("`r ", list_name, "\\$age\\$sd`"))
  expect_false(grepl("\\{[^`]", result))
})
