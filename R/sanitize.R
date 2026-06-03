#' Sanitize object names
#' @export
#' @keywords internal
# sanitize_key()
#
# Converts raw parameter/variable names from model objects or data frames into
# clean, valid R list keys:
#
#   - Lowercased; spaces and non-alphanumeric characters replaced with underscores
#   - Leading/trailing underscores stripped after cleaning
#   - Duplicate keys get a numeric suffix (_2, _3, ...) to ensure uniqueness
#
# Returns a character vector the same length as the input.

sanitize_key <- function(x) {
  if (is.null(x) || length(x) == 0) return(character(0))

  # Simple sanitization: replace spaces/punctuation with underscores
  cleaned <- tolower(x)
  cleaned <- gsub("\\s+", "_", cleaned)
  cleaned <- gsub("[^a-z0-9_]", "", cleaned)
  cleaned <- gsub("^_+|_+$", "", cleaned)

  # Ensure uniqueness  --  duplicates get _2, _3, etc.
  result <- make_unique_keys(cleaned)

  # Always return an unnamed character vector, regardless of input structure
  unname(result)
}

# Appends numeric suffixes to any duplicate values in a character vector.
# Processes keys in order: first occurrence keeps its name, subsequent
# duplicates get _2, _3, etc. Handles cascading collisions (e.g. if "age_2"
# already exists when deduplicating "age") by tracking all assigned keys.
make_unique_keys <- function(keys) {
  assigned <- unname(character(length(keys)))
  used     <- character(0)

  for (i in seq_along(keys)) {
    k <- keys[i]
    if (!(k %in% used)) {
      assigned[i] <- k
    } else {
      j <- 2L
      repeat {
        candidate <- paste0(k, "_", j)
        if (!(candidate %in% used)) {
          assigned[i] <- candidate
          break
        }
        j <- j + 1L
      }
    }
    used <- c(used, assigned[i])
  }

  unname(assigned)
}
