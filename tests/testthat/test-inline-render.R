library(testthat)
library(shiny)
library(htmltools)

source(test_path("../../R/delimiters.R"))
source(test_path("../../R/inline_render.R"))

# Shared test environment with a few values to reference
test_env <- new.env(parent = baseenv())
test_env$x     <- "0.34"
test_env$pval  <- "p < .001"
test_env$n     <- 42L
test_env$results <- list(age = list(estimate = "0.45", p = "p = .023"))

# Helper: extract text content from rendered HTML span
span_text <- function(html_str) {
  gsub('<[^>]+>', '', as.character(html_str))
}

# --- delimiter definitions ---

test_that("get_delimiter returns default for unknown key", {
  d <- get_delimiter("nonexistent")
  expect_equal(d$label, "{expr}")
})

test_that("all three delimiters are defined", {
  expect_true("{}"   %in% names(delimiters))
  expect_true("{{}}" %in% names(delimiters))
  expect_true("`r`"  %in% names(delimiters))
})

# --- render_inline: basic rendering ---

test_that("plain text with no expressions passes through unchanged", {
  result <- render_inline("No expressions here.", test_env, "{}")
  expect_match(as.character(result), "No expressions here\\.")
})

test_that("empty text returns empty preview div", {
  result <- render_inline("", test_env, "{}")
  expect_match(as.character(result), "preview-text")
})

test_that("{} delimiter renders evaluated expression", {
  result <- render_inline("Value is {x}.", test_env, "{}")
  html   <- as.character(result)
  expect_match(html, "inline-value")
  expect_match(html, "0\\.34")
})

test_that("{{}} delimiter renders evaluated expression", {
  result <- render_inline("Value is {{x}}.", test_env, "{{}}")
  html   <- as.character(result)
  expect_match(html, "inline-value")
  expect_match(html, "0\\.34")
})

test_that("`r` delimiter renders evaluated expression", {
  result <- render_inline("Value is `r x`.", test_env, "`r`")
  html   <- as.character(result)
  expect_match(html, "inline-value")
  expect_match(html, "0\\.34")
})

test_that("nested list path renders correctly", {
  result <- render_inline("Estimate: {results$age$estimate}", test_env, "{}")
  expect_match(as.character(result), "0\\.45")
})

test_that("multiple expressions in one string all render", {
  result <- render_inline("n={n}, p={pval}", test_env, "{}")
  html   <- as.character(result)
  expect_match(html, "42")
  expect_match(html, "p &lt; .001")
})

# --- render_inline: error handling ---

test_that("unknown variable produces error span not crash", {
  result <- render_inline("Value is {nonexistent_var}.", test_env, "{}")
  html   <- as.character(result)
  expect_match(html, "inline-error")
  expect_false(grepl("inline-value", html))
})

test_that("invalid R syntax produces error span not crash", {
  result <- render_inline("Value is {1 + + +}.", test_env, "{}")
  html   <- as.character(result)
  expect_match(html, "inline-error")
})

test_that("error span contains the expression text", {
  result <- render_inline("{bad_var}", test_env, "{}")
  expect_match(as.character(result), "bad_var")
})

# --- render_inline: HTML escaping ---

test_that("prose containing HTML special chars is escaped", {
  result <- render_inline("a < b & c > d", test_env, "{}")
  html   <- as.character(result)
  expect_match(html, "&lt;")
  expect_match(html, "&amp;")
  expect_match(html, "&gt;")
})

test_that("expression value containing HTML chars is escaped", {
  test_env$html_val <- "<b>bold</b>"
  result <- render_inline("{html_val}", test_env, "{}")
  expect_match(as.character(result), "&lt;b&gt;")
  expect_false(grepl("<b>", as.character(result)))
})

# --- convert_to_rmd ---

test_that("{} converts to backtick-r syntax", {
  result <- convert_to_rmd("Age was {results$age$estimate}.", "{}")
  expect_equal(result, "Age was `r results$age$estimate`.")
})

test_that("{{}} converts to backtick-r syntax", {
  result <- convert_to_rmd("Age was {{results$age$estimate}}.", "{{}}")
  expect_equal(result, "Age was `r results$age$estimate`.")
})

test_that("`r` delimiter is already correct format, returned unchanged", {
  text   <- "Age was `r results$age$estimate`."
  result <- convert_to_rmd(text, "`r`")
  expect_equal(result, text)
})

test_that("multiple expressions all converted", {
  result <- convert_to_rmd("n={n}, p={pval}", "{}")
  expect_equal(result, "n=`r n`, p=`r pval`")
})

test_that("text with no expressions returned unchanged", {
  text   <- "No expressions here."
  result <- convert_to_rmd(text, "{}")
  expect_equal(result, text)
})
