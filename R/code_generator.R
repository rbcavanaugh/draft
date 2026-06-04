# code_generator.R
#
# Generates the suggested list name that the app uses when a user preps an
# object. The trailing underscore makes it clear in prose that the name refers
# to a prepared draft list rather than the original object.
#
# Setup code strings (e.g. "m1_ <- draft::prep_params(m1)") are now generated
# by each handler's setup_code function in R/class_*.R.

# Suggests a sensible default list name: the object name with a trailing "_".
suggest_list_name <- function(obj_name) {
  paste0(obj_name, "_")
}
