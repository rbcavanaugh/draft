# code_generator.R
#
# Generates copyable R code strings that users paste into their .qmd/.Rmd
# setup chunks. This is the bridge between the app (which shows them the list
# structure) and their document (which needs to recreate it reproducibly).
#
# generate_setup_code() produces the one-liner a user needs:
#   params_model1_ <- draft::prep_params(params_model1)
#
# generate_data_setup_code() does the same for data frames:
#   demo_data_ <- draft::prep_data(demo_data)
#
# Both are internal  --  the app calls them to build the copyable code block
# shown in Panel 2. Users never call these directly.

generate_setup_code <- function(obj_name, list_name) {
  sprintf('%s <- draft::prep_params(%s)', list_name, obj_name)
}

generate_data_setup_code <- function(obj_name, list_name) {
  sprintf('%s <- draft::prep_data(%s)', list_name, obj_name)
}

generate_modelbased_setup_code <- function(obj_name, list_name) {
  sprintf('%s <- draft::prep_modelbased(%s)', list_name, obj_name)
}

generate_performance_setup_code <- function(obj_name, list_name) {
  sprintf('%s <- draft::prep_performance(%s)', list_name, obj_name)
}

# Suggests a sensible default list name from the object name and context.
suggest_list_name <- function(obj_name, type = "parameters_model") {
  paste0(obj_name, "_")
}
