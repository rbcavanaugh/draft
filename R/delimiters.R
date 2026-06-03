# delimiters.R
#
# Defines the supported inline expression delimiter styles. Each entry has:
#   pattern    --  regex with one capture group for the expression content
#   extract    --  function to pull the raw expression from a full match string
#   to_inline  --  function to convert a full match string to `r expr` syntax
#
# The user selects a delimiter in the app settings panel. The selected
# delimiter's pattern is passed to render_inline() and convert_to_rmd().
#
# Adding a new delimiter requires only a new entry in this list  --  no changes
# to render_inline() or convert_to_rmd().

delimiters <- list(

  # Single curly braces: {expr}   --  default
  "{}" = list(
    label     = "{expr}",
    pattern   = "\\{([^{}]+)\\}",
    extract   = function(match) gsub("^\\{|\\}$", "", match),
    to_inline = function(match) {
      expr <- gsub("^\\{|\\}$", "", match)
      paste0("`r ", expr, "`")
    }
  ),

  # Double curly braces: {{expr}}
  "{{}}" = list(
    label     = "{{expr}}",
    pattern   = "\\{\\{([^{}]+)\\}\\}",
    extract   = function(match) gsub("^\\{\\{|\\}\\}$", "", match),
    to_inline = function(match) {
      expr <- gsub("^\\{\\{|\\}\\}$", "", match)
      paste0("`r ", expr, "`")
    }
  ),

  # Native R Markdown syntax: `r expr`
  "`r`" = list(
    label     = "`r expr`",
    pattern   = "`r ([^`]+)`",
    extract   = function(match) gsub("^`r |`$", "", match),
    to_inline = function(match) match  # already correct format
  )
)

# Returns the delimiter definition for a given key, with a fallback to "{}".
get_delimiter <- function(key) {
  if (key %in% names(delimiters)) delimiters[[key]] else delimiters[["{}"]]
}
