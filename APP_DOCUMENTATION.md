# Draft App Documentation

## Overview

Draft is a Shiny app that helps users write inline reports about
statistical models and data. It displays objects from the user’s R
environment, formats their values into structured lists, and allows
users to copy setup code and inline references for use in `.qmd` /
`.Rmd` documents.

## Architecture

The app is organized into three main panels:

- **Panel 1 (Left sidebar)**: Environment browser — shows registered
  object types and scalar values
- **Panel 2 (Centre)**: Object inspector — displays formatted parameters
  or statistics with inline reference paths
- **Panel 3 (Right)**: Text editor + live preview — users type prose
  with inline expressions, see live preview, and copy complete `.qmd`
  chunks

### Handler registry

Support for each object class is encapsulated in a handler registered
via
[`register_handler()`](https://rbcavanaugh.github.io/draft/reference/register_handler.md)
in a `R/class_*.R` file. Adding a new class never requires editing any
shared infrastructure file. Each handler declares:

- `detect` — whether an object belongs to this type
- `class_label` / `size_label` — display strings for the env panel
- `prep` — converts the object to a nested list for inline use
- `assign_result` — which sub-object to store in `render_env` (defaults
  to whole result)
- `setup_code` — R code string for the user’s `.qmd` setup chunk
- `context` — Shiny input values the handler needs (e.g. df mode toggle)
- `controls` — Shiny UI for the inspector header
- `render` — Shiny UI for the inspector body

Registered types in priority order (lower = detected first):

| Priority | Type               | Badge | Handler file          |
|----------|--------------------|-------|-----------------------|
| 10       | `parameters_model` | P     | `class_parameters.R`  |
| 15       | `effectsize`       | ES    | `class_effectsize.R`  |
| 20       | `modelbased`       | MB    | `class_modelbased.R`  |
| 25       | `datawizard`       | DW    | `class_datawizard.R`  |
| 30       | `performance`      | PF    | `class_performance.R` |
| 50       | `dataframe`        | D     | `class_dataframe.R`   |

Priority matters because modelbased, performance, and datawizard objects
inherit from `data.frame`; they must be detected before the dataframe
handler.

------------------------------------------------------------------------

## File Guide

### Core Application Files

#### `launch_app.R`

Entry point for the package. Captures the calling environment and
launches the Shiny app.

**Functions:** - `launch_app(env, port, launch.browser)` \[exported\] —
stores env in `.draft_env`, registers static assets via
`addResourcePath()`, and calls
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) -
[`get_session_env()`](https://rbcavanaugh.github.io/draft/reference/get_session_env.md)
\[exported, internal\] — retrieves the captured environment; used by
`app_server` to access user objects

------------------------------------------------------------------------

#### `app_server.R`

Main server function. Manages reactive state and coordinates data flow
using the handler registry. Type-specific logic has been removed — all
dispatch goes through handlers.

**Key reactive state:** - `env_objects()` — data frame of all
user-visible objects with type classifications - `selected_object()` —
currently selected object name from Panel 1 - `render_env` — named
environment containing assigned prep lists; parent is the session env so
inline expressions can also reach raw session objects -
`inspector_data()` — unified computed data list for the selected
object - `editor_text_d()` — debounced editor text (300ms)

**`inspector_data()` unified shape (for handler-based types):**

    list(
      type             = "parameters_model" | "effectsize" | "modelbased" | "datawizard" | "performance" | "dataframe",
      result           = <output of handler$prep()>,
      error_msg        = character | NULL,
      list_name        = "obj_name_",
      setup_code       = "obj_name_ <- draft::prep_*(obj_name)",
      needs_assignment = TRUE | FALSE,
      obj_class        = class(obj)[1]
    )

For `"scalar"` and `"list"` types (no handler): a simpler list with
`type`, `obj`, `list_name`.

**`inspector_data()` logic:** 1. Get object from env 2.
`classify_object(obj)` → type string 3. `get_handler(type)` → handler 4.
`handler$context(input)` → context list (Shiny inputs the handler needs)
5. `handler$prep(obj, context)` → result (wrapped in tryCatch) 6.
Returns unified data list

**`observeEvent(inspector_data())`:** - Calls
`handler$assign_result(result)` to extract the sub-object to store -
Assigns it to `render_env` under `data$list_name`

**`full_chunk()` reactive:** - Finds all registered-type objects in the
env whose suggested list name appears in editor text - Calls
`handler$setup_code(obj_name, list_name)` for each referenced object -
Returns a complete ```` ```{r}...``` ```` block

**Helper functions:** - `%||%` — null-coalescing operator

------------------------------------------------------------------------

### Handler Registry

#### `aaa_handlers.R`

Defines the registry and the three functions used to interact with it.
Prefixed `aaa_` so it sources before `class_*.R` files at package load
time.

**Functions:** -
`register_handler(type, priority, badge, detect, class_label, size_label, context, prep, assign_result, setup_code, controls, render)`
— stores a handler in `.draft_handlers` env - `get_handler(type)` —
returns one handler by type string, or NULL -
[`get_all_handlers()`](https://rbcavanaugh.github.io/draft/reference/get_all_handlers.md)
— returns all handlers as a list

`.draft_handlers` is a package-level environment
(`new.env(parent = emptyenv())`).

------------------------------------------------------------------------

### Class Files

#### `class_parameters.R`

Handles `parameters_model` objects — output of
[`parameters::model_parameters()`](https://easystats.github.io/parameters/reference/model_parameters.html).
Covers frequentist and Bayesian models; handles standard and correlation
parameter tables.

**Exported functions:** - `prep_params(params_obj)` — formats a
`parameters_model` into a nested named list. Calls
`format(params_obj, zap_small=TRUE)`, lowercases/cleans column names,
creates sanitized keys from the `parameter` column (or
`parameter1`/`parameter2` for correlations), calls
[`params_df_to_list()`](https://rbcavanaugh.github.io/draft/reference/params_df_to_list.md) -
`params_df_to_list(params)` — converts a formatted data frame to a
nested list; one element per row keyed by the `key` column; skips NA /
empty values

**Internal helpers:** - `is_present(x)` — TRUE if value is non-NA and
non-empty string

**Render:** - `render_model_inspector(data)` — reads `data$result` (the
prep output); shows one chip row per parameter; calls
`render_model_list_table()` for the bottom preview

**Handler:** priority 10, badge “P”

------------------------------------------------------------------------

#### `class_dataframe.R`

Handles plain data frames and tibbles. Two modes: summary (computed
statistics) and raw (direct `$col` access paths).

**Exported functions:** - `prep_data(df, cat_threshold)` — summarises
each column; columns with `cat_threshold` or fewer unique non-missing
values are treated as categorical (default 10)

**Internal helpers:** - `summarise_column(x, cat_threshold)` —
dispatches to continuous or categorical -
`is_categorical(x, cat_threshold)` — classification logic -
`summarise_continuous(x)` — returns `mean`, `sd`, `median`, `min`,
`max`, `n`, `n_missing` - `summarise_categorical(x)` — returns `n`,
`n_missing`, and per-level `n`/`pct` sub-lists -
`raw_columns(df, df_name)` — returns a data frame of column paths for
raw mode - `column_type_label(x)` — returns a short type string for raw
mode display - `render_summary_chips(summary, base)` — chips for a
single column’s summary - `render_raw_columns_table(raw_df)` — raw mode
column list

**Render:** - `render_dataframe_inspector(data)` — reads
`data$result$mode` (“summary” or “raw”); in summary mode shows chip rows
and calls `render_data_list_table()` for the preview

**Handler:** priority 50, badge “D”,
`assign_result = function(result) result$summary` (only the summary list
is stored in `render_env`, not the full result), context reads
`input$df_mode`

------------------------------------------------------------------------

#### `class_modelbased.R`

Handles modelbased objects: `estimate_means`, `estimate_contrasts`,
`estimate_slopes`.

**Exported functions:** - `prep_modelbased(obj)` — converts to a nested
named list; column names are never hardcoded; label columns (row
identifiers) detected via `attr(obj, "by")` and character/factor
columns; value columns are everything numeric

**Internal helpers:** - `detect_label_cols(obj, df)` — identifies
identifier vs value columns - `build_row_keys(df, label_cols)` — builds
row keys; contrasts get “Level1_vs_Level2” format; single moderator
levels use the level value; otherwise pastes label columns

**Render:** - `render_modelbased_inspector(data)` — reads `data$result`;
section title adapts to object class (e.g. “Marginal Means”,
“Contrasts”, “Marginal Effects”); calls `render_modelbased_table()` for
the preview - `render_modelbased_table(mb_list)` — generic table; first
column is row key, remaining columns are whatever value fields the
object provides

**Handler:** priority 20, badge “MB”

------------------------------------------------------------------------

#### `class_performance.R`

Handles performance objects: `model_performance` and
`compare_performance`.

**Exported functions:** - `prep_performance(obj)` — dispatches to
`prep_model_performance()` or `prep_compare_performance()` based on
class

**Internal helpers:** - `prep_model_performance(df)` — flattens
single-row output to a flat named list of formatted metric values keyed
by lowercased column name - `prep_compare_performance(df)` — nested list
keyed by model name (`Name` column); each element contains the model’s
numeric metrics

**Render:** - `render_performance_inspector(data)` — reads `data$result`
and `data$obj_class`; `compare_performance` shows one chip row per
model; single model shows all metrics as one flat chip row; calls
`render_performance_table()` for the preview -
`render_performance_table(perf_list)` — generic table using
`preview_table()`

**Handler:** priority 30, badge “PF”

------------------------------------------------------------------------

#### `class_effectsize.R`

Handles effectsize package objects — any object inheriting from
`effectsize_table`. Covers `effectsize_difference` (e.g. `cohens_d`,
`hedges_g`), `effectsize_anova` (e.g. `eta_squared`, `omega_squared`),
and `effectsize_table` (e.g. `cramers_v`, `phi`).

**Exported functions:** - `prep_effectsize(obj)` — dispatches to
`prep_effectsize_flat()` (single-row or no `Parameter` column) or
`prep_effectsize_multi()` (multi-row with `Parameter` column)

**Internal helpers:** - `.es_skip_cols` — `c("Parameter", "CI")` —
columns excluded from values (CI is a metadata constant for the
confidence level, not a reportable value) - `prep_effectsize_flat(df)` —
flat named list of formatted values for single-effect objects -
`prep_effectsize_multi(df)` — nested list keyed by `Parameter` for
multi-effect objects (e.g. `eta_squared` with several predictors)

**Render:** - `render_effectsize_inspector(data)` — flat result shows
all fields as one chip row; multi-row result shows one chip row per
parameter; calls `render_effectsize_table()` -
`render_effectsize_table(es_list)` — generic preview table

**Handler:** priority 15, badge “ES”

------------------------------------------------------------------------

#### `class_datawizard.R`

Handles `parameters_distribution` objects — output of
[`datawizard::describe_distribution()`](https://easystats.github.io/datawizard/reference/describe_distribution.html).
Supports both flat (no `by` argument) and stratified (with `by`
argument) shapes.

**Exported functions:** - `prep_distribution(obj)` — detects grouping by
checking for columns before `Variable`; dispatches to
`prep_distribution_flat()` or `prep_distribution_stratified()`

**Internal helpers:** - `prep_distribution_flat(df, value_cols)` — keys
by `Variable`, all numeric columns after `Variable` become formatted
value fields at the leaf level -
`prep_distribution_stratified(df, by_cols, value_cols)` — keys first by
unique group values (from `by` columns), then calls
`prep_distribution_flat()` for each group’s rows. Groups are sanitized
from `unique(raw_groups)` — not from all rows — to avoid deduplication
suffixes on repeated group names

**Render:** - `render_distribution_inspector(data)` — stratified:
section headers per group with variable rows inside; flat: single
section of variable rows; calls `render_distribution_table()` for the
preview - `render_distribution_table(dist_list, stratified)` — table
with Group/Variable columns for stratified, Variable column for flat

**Handler:** priority 25, badge “DW”

------------------------------------------------------------------------

### Object Classification

#### `classify_objects.R`

Classifies objects using the handler registry and builds the env panel
data frame. No type-specific logic lives here — all dispatch is via the
registry.

**Exported functions:** - `list_objects(env)` — returns a data frame
(name, type, class_label, size_label) for all visible non-dot objects;
uses `handler$class_label(obj)` and `handler$size_label(obj)` for
registered types; falls back to `make_fallback_*` for
scalar/list/other - `classify_object(obj)` — walks handlers in priority
order; returns the first type whose `detect(obj)` returns TRUE; falls
back to “scalar”, “list”, or “other”

**Internal helpers:** - `make_fallback_class_label(obj, type)` — class
labels for non-handler types - `make_fallback_size_label(obj, type)` —
size labels for non-handler types - `detect_list_subtype(obj)` —
categorises named lists as “model_list”, “data_list”, or “generic_list”
for the list inspector’s bottom preview

------------------------------------------------------------------------

### Code Generation

#### `code_generator.R`

Single function; setup code strings are generated by each handler’s
`setup_code` field.

**Functions:** - `suggest_list_name(obj_name)` — returns
`paste0(obj_name, "_")`; the trailing underscore distinguishes prep list
names from the original object names

------------------------------------------------------------------------

### Name Sanitization

#### `sanitize.R`

**Exported functions:** - `sanitize_key(x)` — converts raw names to
valid R list keys: lowercased, spaces and non-alphanumeric characters
replaced with underscores, leading/trailing underscores stripped,
duplicate keys get numeric suffixes (`_2`, `_3`, …)

------------------------------------------------------------------------

### Display and Rendering

#### `render_inspector_panel.R`

Builds Panel 2 (Object Inspector). Contains only the top-level
dispatcher, shared helpers, and renderers for non-handler types (scalar,
list). Per-class renderers live in their respective `class_*.R` files.

**Dispatcher:** - `render_inspector_content(data)` — calls
`handler$render(data)` for registered types; falls back to
`render_scalar_inspector()` or `render_list_inspector()`

**Shared helpers used by all class renderers:** -
`value_chip(label, value, path)` — renders a copyable chip: label \|
value \| copy button; copy button carries `{path}` as `data-clipboard`
attribute - `refer_as_bar(list_name)` — “Refer to this object as
`list_name$...`” banner - `inspector_error(title, msg)` — standardised
error display div - `preview_table(headers, body_rows)` — wraps rows in
a standard `.preview-table` structure

**List inspector (non-handler):** - `render_list_inspector(data)` —
detects subtype and delegates to `render_model_list_chips`,
`render_data_list_chips`, or `render_generic_list_chips` for the top
half; `render_model_list_table` or `render_data_list_table` for the
bottom half - `render_model_list_chips(obj, list_name)` — chips for a
prep_params-style list - `render_model_list_table(obj)` — table for a
prep_params-style list - `render_data_list_chips(obj, list_name)` —
chips for a prep_data-style list - `render_data_list_table(obj)` —
Variable \| Type \| Summary table -
`render_generic_list_chips(obj, list_name)` — flat path chips for
unrecognised lists

**Scalar inspector:** - `render_scalar_inspector(data)` — single chip
showing the value and its name as the path

**Other:** - `render_unsupported()` — fallback for unrecognised types -
`render_setup_block(code, list_name)` — copyable setup code block (used
by Panel 3)

------------------------------------------------------------------------

#### `render_env_panel.R`

Builds Panel 1 (environment object list). Reads badge text and type
ordering directly from the handler registry — no hardcoded type lists.

**Functions:** - `render_object_list(objs, selected_nm)` — filters to
registered types + scalar; sorts by handler priority; renders clickable
rows with badge, name, and metadata

------------------------------------------------------------------------

#### `render_editor_panel.R`

Builds Panel 3 (text editor + live preview + setup chunk button).

**Functions:** - `render_editor_panel_body()` — textarea, settings
toggle, live preview area, hidden converted-text field, setup chunk
footer

------------------------------------------------------------------------

### Expression Rendering

#### `inline_render.R`

Evaluates inline expressions and renders styled HTML for the live
preview.

**Functions:** - `format_scalar(x)` — formats a scalar for display;
numeric values go through
`insight::format_value(x, zap_small = TRUE, protect_integers = TRUE)` (2
dp, no scientific notation); non-numeric values are coerced to
character - `format_col(val, col_name)` — formats a single value for a
named column; p-value columns (matching `.p_col_pattern`: `p`,
`p_value`, `p_adj`, `pd`, `bf`, etc.) are routed through
[`insight::format_p()`](https://easystats.github.io/insight/reference/format_p.html)
giving 3 dp and `< .001`; all other columns use `format_value()` with 2
dp. Used by all `class_*.R` prep functions except `class_parameters.R`
(which delegates formatting to `parameters::format()`) -
`.p_col_pattern` — regex
`^(p|p_value|p\\.value|p_adj|p_adjusted|pd|bf)$`; defines which column
names are treated as p-values -
`render_inline(text, env, delimiter_key)` — splits text into prose and
expressions; HTML-escapes prose; evaluates each expression in `env`;
returns styled HTML - `render_expression(expr_str, env)` — evaluates a
single expression; success → `<span class="inline-value">`; error →
`<span class="inline-error">` with tooltip -
`convert_to_rmd(text, delimiter_key)` — converts `{expr}` to
`` `r expr` `` for copying

------------------------------------------------------------------------

#### `delimiters.R`

Defines the available inline expression syntaxes:
[`{}`](https://rdrr.io/r/base/Paren.html), `{{}}`, and `` `r ` ``.

**Functions:** - `get_delimiter(key)` — returns a list with `pattern`,
`extract()`, `to_inline()` functions for the chosen delimiter style

------------------------------------------------------------------------

### Utility Files

#### `sample_data.R`

- `load_sample_objects(env)` — called by `app_server.R` when the session
  environment contains no visible objects. Populates `env` with a small
  set of representative objects (`sample_lm_params`, `sample_means`,
  `sample_corr`, `sample_data`) so new users see a working example
  immediately rather than a blank panel. Wrapped in `tryCatch` —
  silently does nothing if any suggested package is unavailable.

------------------------------------------------------------------------

#### `precompute_models.R`

- `precompute_model_params(env)` — scans env for model objects via
  [`insight::is_model()`](https://easystats.github.io/insight/reference/is_model.html),
  caches `model_parameters()` output as `.model_params_<name>`
  variables. Currently not called at app startup; reserved for future
  use.

------------------------------------------------------------------------

## Data Flow

    USER SELECTS OBJECT (Panel 1)
      |
      v
    selected_object(nm) updated
      |
      v
    inspector_data() reactive fires
      |- get(nm, envir = get_session_env())         retrieve object
      |- classify_object(obj)                        walk registry by priority
      |- get_handler(type) -> handler
      |- handler$context(input)                      extract Shiny inputs needed
      |- handler$prep(obj, context) -> result        convert to named list
      |- list_name = suggest_list_name(nm)           e.g. "m1_"
      `- return unified data list
      |
      v
    observeEvent(inspector_data()) fires
      |- handler$assign_result(result)               extract sub-object to store
      `- assign(list_name, val, envir = render_env)  e.g. render_env$m1_ = list(...)
      |
      v
    output$inspector_content updated
      `- render_inspector_content(data)
         `- handler$render(data)
            `- refer_as_bar + chip rows + preview table


    USER TYPES IN EDITOR (Panel 3)
      |
      v
    input$editor_text updated -> editor_text_d() debounced 300ms
      |
      |- output$editor_preview
      |  `- render_inline(text, render_env, delim)   evaluate expressions -> styled HTML
      |
      `- output$rmd_text
         `- convert_to_rmd(text, delim)              {expr} -> `r expr`


    USER CLICKS COPY CHUNK BUTTON
      |
      v
    full_chunk() reactive fires
      |- find all registered-type objects in env
      |- for each: suggest_list_name(nm) -> list_name
      |- if list_name appears in editor text:
      |  `- handler$setup_code(nm, list_name)        e.g. "m1_ <- draft::prep_params(m1)"
      `- return ```{r}\nsetup_lines\n```

------------------------------------------------------------------------

## CSS and JavaScript

- **`inst/www/styles.css`** — three-panel layout, chip styles, table
  styles, badge colours. Badge colour classes follow the pattern
  `.badge-{type}` (e.g. `.badge-parameters`, `.badge-effectsize`,
  `.badge-datawizard`). `.empty-state-error` styles the red message
  shown when the session environment is empty before sample objects
  load.
- **`inst/www/clipboard.js`** — reads `data-clipboard` from buttons;
  copies to clipboard on click

------------------------------------------------------------------------

## Key Design Decisions

1.  **Handler registry** — adding a new class only requires a
    `R/class_*.R` file; no shared files need changing. The `aaa_` prefix
    on `aaa_handlers.R` ensures it sources before class files at package
    load time.

2.  **Unified `inspector_data()` shape** — all handler-based types
    return the same fields (`type`, `result`, `error_msg`, `list_name`,
    `setup_code`, `needs_assignment`, `obj_class`). Handlers don’t need
    to know about each other.

3.  **`assign_result` override** — the dataframe handler stores only
    `result$summary` in `render_env`, not the full result. This keeps
    inline paths clean while the full result (mode, raw columns, obj
    reference) is available during rendering.

4.  **Shared render helpers in `render_inspector_panel.R`** —
    `value_chip`, `refer_as_bar`, `inspector_error`, `preview_table`,
    `render_model_list_*`, `render_data_list_*` are shared utilities.
    Class files call them but don’t redefine them.

5.  **Trailing underscore naming** — `suggest_list_name()` returns
    `obj_name_`; the underscore visually distinguishes the prep list
    from the original object in prose.

6.  **Separation of computation and display** — `inspector_data()`
    computes, `handler$render()` displays. Handlers never run `prep`
    inside their render function.

7.  **Priority-based detection** —
    [`classify_object()`](https://rbcavanaugh.github.io/draft/reference/classify_object.md)
    walks handlers in priority order so subclass objects (modelbased,
    performance inherit from data.frame) are detected first.

------------------------------------------------------------------------

## Adding Tests for a New Class

Each class gets one test file: `tests/testthat/test-class-{type}.R`. The
file follows five sections in order. The existing files
(`test-class-parameters.R`, `test-class-dataframe.R`,
`test-class-modelbased.R`, `test-class-performance.R`,
`test-class-effectsize.R`, `test-class-datawizard.R`) are the canonical
examples.

### Section 1 — Skip guard and fixtures

If the class depends on a suggested package, guard the entire file at
the top:

``` r

skip_if_not_installed("mypackage")
library(mypackage)
```

Then create two or three representative objects that cover the main
sub-types your handler must handle (e.g. lm vs glm, single model vs
comparison, means vs contrasts).

``` r

obj_a <- mypackage::build_thing(lm(mpg ~ wt, mtcars))
obj_b <- mypackage::build_thing(glm(am ~ wt, mtcars, family = binomial))
```

**Fixture gotcha — avoid digit-starting keys.** If rows/levels will
become list keys used in `{list_$key$field}` inline paths, their string
representation must be valid as a bare R name. `iris$Species` levels
(“setosa”, “versicolor”, “virginica”) are safe; `mtcars$cyl` levels
(“4”, “6”, “8”) produce invalid syntax in `$` paths. Use the safe
fixture or quote the key with backticks in your test assertions.

------------------------------------------------------------------------

### Section 2 — Classification

Check that
[`classify_object()`](https://rbcavanaugh.github.io/draft/reference/classify_object.md)
returns the right type string and that it doesn’t accidentally match as
`"dataframe"` (important if your object inherits from `data.frame`):

``` r

test_that("classify_object returns 'mytype' for obj_a", {
  expect_equal(classify_object(obj_a), "mytype")
})

test_that("mytype objects are not mis-classified as dataframe", {
  expect_false(classify_object(obj_a) == "dataframe")
})
```

------------------------------------------------------------------------

### Section 3 — `prep_*` structure

Test the shape of the prep output, not specific numeric values (which
change between package versions). Check:

- Return type is a named list
- Length matches the expected number of rows/entries
- Each element is itself a named list of character strings
- Key names follow the expected pattern (e.g. `_vs_` for contrasts)

``` r

test_that("prep_mytype returns a named list", {
  result <- prep_mytype(obj_a)
  expect_type(result, "list")
  expect_gt(length(result), 0)
  expect_false(is.null(names(result)))
})

test_that("each element is a named sub-list of character strings", {
  result <- prep_mytype(obj_a)
  for (nm in names(result)) {
    expect_type(result[[nm]], "list")
    for (field in names(result[[nm]])) {
      expect_type(result[[nm]][[field]], "character")
    }
  }
})
```

**Field name gotcha.** Always discover the real field names by running
the prep function interactively before writing assertions.
`parameters::format()` returns `"Coefficient"` (not `"Estimate"`) for
lm; CI columns may be `"95_CI"` not `"ci_low"`/`"ci_high"`. Use
`names(result$wt)` to inspect. Write flexible assertions where fields
may vary across package versions:

``` r

# Flexible CI check — name varies by parameters version
ci_fields <- grep("ci", names(result$wt), value = TRUE)
expect_gt(length(ci_fields), 0)
```

------------------------------------------------------------------------

### Section 4 — APA formatting

Every class must assert that its prep output follows APA numeric
conventions. Add this block after the structure tests:

``` r

# --- Formatting: decimal places --------------------------------------------

test_that("prep_mytype non-p values never exceed 2 decimal places", {
  result  <- prep_mytype(obj_a)
  all_vals <- unlist(result)
  # Exclude p-value fields — they legitimately use 3 decimal places
  p_names  <- grepl("(\\.p|^p)$", names(all_vals))
  values   <- trimws(all_vals[!p_names])
  values   <- values[!grepl("^[<>]", values)]
  bad      <- values[grepl("\\.[0-9]*[1-9][0-9]{2,}", values)]
  expect_equal(length(bad), 0L,
               info = paste("Over-precise values:", paste(bad, collapse = ", ")))
})

# If the class produces p-values, also assert they are APA-formatted:
test_that("prep_mytype p values are APA formatted (3 dp or < .001)", {
  result   <- prep_mytype(obj_a)
  all_vals <- unlist(result)
  p_vals   <- trimws(all_vals[grepl("(\\.p|^p)$", names(all_vals))])
  # Each p-value must be a threshold string or have exactly 3 decimal places
  valid <- grepl("^[<>]\\s*[0-9.]+$|\\.[0-9]{3}$", p_vals)
  expect_true(all(valid),
              info = paste("Badly formatted p-values:", paste(p_vals[!valid], collapse = ", ")))
})
```

**Regex notes:** - `\\.[0-9]*[1-9][0-9]{2,}` catches values with 3+
significant decimal digits (e.g. `0.123`) but not leading-zero values
like `0.001` (only 1 significant decimal digit) - The p-value name
pattern `(\\.p|^p)$` matches bare `p` keys and
[`unlist()`](https://rdrr.io/r/base/unlist.html)-generated names like
`contrast_8_vs_6.p` - `class_parameters.R` delegates to
`parameters::format()` which handles both conventions natively — its
test only needs the non-p check

------------------------------------------------------------------------

### Section 5 — Handler metadata

Test the handler’s `setup_code()` and `badge` directly via
[`get_handler()`](https://rbcavanaugh.github.io/draft/reference/get_handler.md):

``` r

test_that("suggest_list_name appends trailing underscore", {
  expect_equal(suggest_list_name("my_obj"), "my_obj_")
})

test_that("mytype handler setup_code is correct", {
  h    <- get_handler("mytype")
  code <- h$setup_code("my_obj", "my_obj_")
  expect_equal(code, "my_obj_ <- draft::prep_mytype(my_obj)")
})

test_that("mytype handler has correct badge", {
  h <- get_handler("mytype")
  expect_equal(h$badge, "XY")
})
```

------------------------------------------------------------------------

### Section 6 — Full inline pipeline

This is the highest-value test: it exercises `prep_*` → assign to env →
`render_inline()` → `convert_to_rmd()` as one chain, matching what the
app does at runtime.

``` r

test_that("value resolves in render_inline", {
  result    <- prep_mytype(obj_a)
  list_name <- suggest_list_name("my_obj")
  first_key <- names(result)[1]

  env <- new.env(parent = baseenv())
  assign(list_name, result, envir = env)

  first_field <- names(result[[first_key]])[1]
  expected    <- result[[first_key]][[first_field]]
  text <- paste0("Value: {", list_name, "$", first_key, "$", first_field, "}")

  html <- as.character(render_inline(text, env, "{}"))
  expect_match(html, "inline-value")
  expect_match(html, htmltools::htmlEscape(expected), fixed = TRUE)
})

test_that("convert_to_rmd produces correct backtick-r syntax", {
  result    <- prep_mytype(obj_a)
  list_name <- suggest_list_name("my_obj")
  first_key <- names(result)[1]
  first_fld <- names(result[[first_key]])[1]

  text       <- paste0("Value: {", list_name, "$", first_key, "$", first_fld, "}.")
  result_rmd <- convert_to_rmd(text, "{}")
  expect_false(grepl("\\{[^`]", result_rmd))
  expect_match(result_rmd, paste0("`r ", list_name, "\\$", first_key, "\\$", first_fld, "`"))
})
```

**Case preservation gotcha.** `summarise_categorical()` uses
[`table()`](https://rdrr.io/r/base/table.html) which preserves original
case. Level `"Female"` produces key `"Female"`, not `"female"`. Check
actual keys with `names(result$col)` before writing string assertions.

------------------------------------------------------------------------

### Checklist for a new class test file

`skip_if_not_installed()` guard if package is not in hard `Imports`

Fixtures cover all sub-types handled by `detect`

Fixtures use row/level values that are valid bare R identifiers

[`classify_object()`](https://rbcavanaugh.github.io/draft/reference/classify_object.md)
correct type and no false `"dataframe"` match

`prep_*` shape: named list, sub-lists, character strings

Field names verified interactively before hardcoding

APA formatting: non-p values ≤ 2 dp; p-values exactly 3 dp or `< .001`

If class has p-values, positive assertion that they ARE formatted to 3
dp

[`get_handler()`](https://rbcavanaugh.github.io/draft/reference/get_handler.md)
badge and `setup_code()` assertions

Full pipeline: assign → `render_inline` → `convert_to_rmd`
