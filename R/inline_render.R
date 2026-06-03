# inline_render.R
#
# render_inline() is the engine behind the live preview panel. Given a text
# string containing delimited R expressions and an environment to evaluate
# them in, it returns an HTML string where:
#
#   - Surrounding prose is HTML-escaped (prevents XSS from user-typed text)
#   - Each valid expression is replaced by a styled <span> showing its value
#   - Expressions that fail to evaluate get a red error span with a tooltip
#
# The approach splits the text into alternating plain/expression segments
# rather than using a single substitution pass, so that HTML-escaping the
# prose does not interfere with the delimiter patterns.
#
# convert_to_rmd() is the companion function used by the copy button. It
# replaces all delimited expressions with standard `r expr` inline syntax
# so the copied text is valid R Markdown / Quarto.

# Converts \n to <br> tags so multi-line textarea text renders correctly in HTML.
newlines_to_br <- function(x) gsub("\n", "<br>", x, fixed = TRUE)

#' @keywords internal
render_inline <- function(text, env, delimiter_key = "{}") {
  if (!nzchar(text)) return(shiny::HTML("<div class='preview-text'></div>"))

  delim   <- get_delimiter(delimiter_key)
  pattern <- delim$pattern

  # Split text into segments: odd-indexed = plain prose, even-indexed = matches
  parts   <- strsplit(text, pattern, perl = TRUE)[[1]]
  matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]

  # No expressions found  --  return escaped prose as-is
  if (length(matches) == 0) {
    return(shiny::HTML(paste0(
      "<div class='preview-text'>",
      newlines_to_br(htmltools::htmlEscape(text)),
      "</div>"
    )))
  }

  # Interleave: plain[1], match[1], plain[2], match[2], ...
  html_parts <- character(length(parts) + length(matches))

  plain_idx <- seq(1, length(html_parts), by = 2)
  match_idx <- seq(2, length(html_parts), by = 2)

  html_parts[plain_idx] <- newlines_to_br(htmltools::htmlEscape(parts))
  html_parts[match_idx] <- vapply(matches, function(m) {
    expr_str <- delim$extract(m)
    render_expression(expr_str, env)
  }, character(1))

  shiny::HTML(paste0(
    "<div class='preview-text'>",
    paste(html_parts, collapse = ""),
    "</div>"
  ))
}

# Evaluates a single expression string in the given environment and returns
# a styled HTML span. On error, returns a red span with the error as a tooltip.
render_expression <- function(expr_str, env) {
  result <- tryCatch(
    {
      val <- eval(parse(text = expr_str), envir = env)
      # NULL means the path doesn't exist  --  treat as an error so the user
      # sees a visible signal rather than a silent empty span.
      if (is.null(val) || length(val) == 0) {
        return(make_error_span(expr_str, "NULL (path not found)"))
      }
      # Collapse vectors to a readable string; cap at 5 elements
      if (length(val) > 5) {
        val <- paste0(paste(val[1:5], collapse = ", "), " ...")
      } else {
        val <- paste(val, collapse = ", ")
      }
      paste0('<span class="inline-value">', htmltools::htmlEscape(as.character(val)), '</span>')
    },
    error = function(e) make_error_span(expr_str, conditionMessage(e))
  )
  result
}

make_error_span <- function(expr_str, message) {
  paste0(
    '<span class="inline-error" title="',
    htmltools::htmlEscape(message),
    '">',
    htmltools::htmlEscape(expr_str),
    '</span>'
  )
}

#' @keywords internal
convert_to_rmd <- function(text, delimiter_key = "{}") {
  delim <- get_delimiter(delimiter_key)

  # Already in `r expr` format  --  nothing to convert
  if (delimiter_key == "`r`") return(text)

  # Use gregexpr + regmatches replacement  --  gsub doesn't accept function replacement
  m <- gregexpr(delim$pattern, text, perl = TRUE)
  regmatches(text, m) <- list(vapply(
    regmatches(text, m)[[1]],
    delim$to_inline,
    character(1)
  ))
  text
}
