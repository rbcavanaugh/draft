# Draft App Documentation

## Overview

Draft is a Shiny app that helps users write inline reports about statistical models. It displays objects from the user's R environment, formats model parameters and data summaries, and allows users to copy setup code and inline references for use in .qmd documents.

## Architecture

The app is organized into three main panels:
- **Panel 1 (Left sidebar)**: Environment object browser - shows parameters_model, dataframe, and scalar objects
- **Panel 2 (Center)**: Object inspector - displays formatted model parameters or data summaries with inline reference paths
- **Panel 3 (Right)**: Text editor + live preview - users type text with inline expressions, see live preview, and copy complete .qmd chunks

---

## File Guide

### Core Application Files

#### `app_ui.R`
Defines the three-panel UI layout using bslib for responsive design.

**Functions:**
- `app_ui()` - Top-level UI function that creates the page structure
  - Returns a bslib page_fillable with sidebar layout
  - Sidebar contains Panel 1 (environment browser)
  - Main content area contains Panels 2 & 3 (inspector + editor)

**Dependencies:** `app_ui()` → rendered by `launch_app()`

---

#### `app_server.R`
Main server logic that manages reactive state and coordinates data flow between all components.

**Key Reactive State:**
- `env_objects()` - list of all user environment objects with classifications
- `selected_object()` - currently selected object name from left panel
- `inspector_data()` - computed object for display (formatted parameters, summaries, etc.)
- `editor_text_d()` - debounced editor text (300ms delay)
- `render_env` - named environment containing assigned lists for inline expression evaluation

**Functions:**
- `list_objects(env)` - Gets all objects from environment
- `selected_object(nm)` - Tracks which object user clicked
- `inspector_data()` [reactive] - Core data computation:
  - Gets object from user's environment
  - Classifies its type
  - For parameters_model: calls `prep_params()` → stores result in `render_env`
  - For dataframe: calls `prep_data()` → stores result in `render_env`
  - Returns data list with type, formatted values, setup code, list_name
  
- **Observer: `input$refresh_env`** - Re-lists objects when refresh button clicked (legacy)

- **Observer: `inspector_data()`** - When inspector data changes, assigns formatted list to `render_env`:
  - For parameters_model with `needs_assignment==TRUE`: `assign(list_name, params_list, envir=render_env)`
  - For dataframe in summary mode: `assign(list_name, summary_list, envir=render_env)`

- `full_chunk()` [reactive] - Generates complete .qmd chunk for copying:
  - Gets editor text
  - Gets all environment objects (parameters_model + dataframe types)
  - For each object, generates suggested list name using `suggest_list_name()`
  - Checks if that list name appears in editor text
  - Generates setup code for referenced objects using `generate_setup_code()` or `generate_data_setup_code()`
  - Returns complete ```{r}..._``` block with setup code

- `output$env_object_list` - Renders left panel via `render_object_list(env_objects(), selected_object())`

- `output$inspector_controls` - Renders inspector header controls (df mode toggle) via `render_inspector_controls()`

- `output$inspector_content` - Renders inspector body via `render_inspector_content(inspector_data())`

- `output$editor_preview` - Renders live preview via `render_inline(editor_text_d(), render_env, delim)`

- `output$rmd_text` - Hidden field: stores converted editor text via `convert_to_rmd(input$editor_text, delim)`

- `output$setup_chunk_ui` - Renders setup chunk button that copies `full_chunk()`

**Helper Functions:**
- `extract_referenced_names(text, available_names)` - Finds which object names appear in editor text using regex word boundaries
- `%||%` - Null coalescing operator

**Data Flow:**
```
User selects object → selected_object() updated → inspector_data() fires
  → classify_object() determines type
  → prep_params() or prep_data() called
  → result stored in render_env via observeEvent
  → render_inspector_content() displays it
  
User types in editor → editor_text_d() updates → render_inline() previews
User clicks copy → full_chunk() finds referenced objects → returns setup + code block
```

---

### Object Classification & Detection

#### `classify_objects.R`
Detects object types and generates UI labels/sizes for the left panel.

**Functions:**
- `list_objects(env)` - Creates data.frame of all user environment objects
  - Returns: name, type, class_label, size_label
  - Calls `classify_object()` on each object
  - **Receives:** environment (usually `get_session_env()`)
  - **Returns to:** `env_objects()` reactive in app_server

- `classify_object(obj)` - Determines object type (order matters: check specific classes first)
  - Checks: `inherits(obj, "parameters_model")` → "parameters_model"
  - Checks: `is.data.frame(obj)` → "dataframe"
  - Checks: `is.list(obj) && !is.null(names(obj))` → "list"
  - Checks: `is.atomic(obj) && length(obj)==1` → "scalar"
  - Default: "other"
  - **Returns to:** app_server's inspector_data() and render_object_list()

- `make_class_label(obj, type)` - Human-readable class badge text
  - parameters_model → "parameters"
  - dataframe → "data.frame" or "tibble"
  - Returns to: `list_objects()`

- `make_size_label(obj, type)` - Size description
  - dataframe → "rows × cols"
  - parameters_model → "n parameters"
  - list → "n elements"
  - Returns to: `list_objects()`

- `detect_list_subtype(obj)` - Categorizes lists as model_list, data_list, or generic
  - Returns to: `render_list_inspector()` for tab display

---

### Parameter Formatting

#### `prep_model.R`
Converts parameters_model objects (from parameters::model_parameters()) into nested named lists for inline reporting.

**Functions:**
- `prep_params(params_obj)` [exported] - Main entry point:
  - Calls `format(params_obj, zap_small=TRUE)` → `dplyr::bind_rows()` to get formatted dataframe
  - Lowercases column names
  - Removes spaces and punctuation: `"95% CI"` → `"x95ci"`
  - Creates keys: if "parameter" column exists, uses that; else if "parameter1" & "parameter2" exist (correlations), combines them
  - Calls `sanitize_key()` on parameter names
  - Calls `params_df_to_list(raw)` to convert to nested list
  - **Receives:** parameters_model object from user's environment (via app_server's inspector_data)
  - **Returns to:** inspector_data() which stores in `data$params_list`

- `params_df_to_list(params)` [exported] - Converts formatted dataframe to nested list:
  - One list element per row, named by sanitized parameter key
  - Each element contains all non-NA, non-empty columns as sub-values
  - **Receives:** formatted dataframe from `prep_params()`
  - **Returns to:** prep_params()

- `is_present(x)` - Helper: checks if value is non-NA, non-empty string

---

#### `prep_data.R`
Summarizes dataframes for inline reporting.

**Functions:**
- `prep_data(df)` [exported] - Summarizes a dataframe:
  - For continuous columns: mean, sd, median, n
  - For categorical columns: n, per-level percentages (capped at 5 levels)
  - Returns nested named list
  - **Receives:** dataframe from user's environment (via app_server's inspector_data)
  - **Returns to:** inspector_data() which stores in `data$summary_list`

- `raw_columns(df, name)` - Returns raw column information for "raw columns" dataframe view

- `is_numeric_col(col)` - Helper: checks if column is numeric
- `format_numeric(x)` - Helper: formats numbers for display
- `format_pct(x)` - Helper: formats percentages

---

### Code Generation

#### `code_generator.R`
Generates the one-liner setup code that users paste into their .qmd setup chunks.

**Functions:**
- `generate_setup_code(obj_name, list_name)` - Creates setup line for parameters_model:
  - Returns: `"results_m_lm <- draft::prep_params(params_m_lm)"`
  - **Receives:** original object name and suggested list name (from app_server's full_chunk)
  - **Returns to:** full_chunk() and inspector_data()

- `generate_data_setup_code(obj_name, list_name)` - Creates setup line for dataframe:
  - Returns: `"stats_data <- draft::prep_data(data)"`
  - **Receives:** object and list names
  - **Returns to:** full_chunk() and inspector_data()

- `suggest_list_name(obj_name, type)` - Generates natural list variable name:
  - parameters_model: `"results_params_m_lm"` (from `params_m_lm`)
  - dataframe: `"stats_data"` (from `data`)
  - **Returns to:** inspector_data() and full_chunk()

---

### Pre-computation

#### `precompute_models.R`
Pre-computes model parameters for all model objects in the session environment at app startup.

**Functions:**
- `precompute_model_params(env)` [internal] - Scans env for model objects and caches parameters:
  - Uses `insight::is_model()` to detect model objects
  - Calls `parameters::model_parameters()` for each detected model
  - Caches results in env as `.model_params_<name>` variables
  - Returns a named lookup list mapping object names to cached parameter names
  - **Receives:** user session environment (from launch_app)
  - **Returns to:** app startup / launch_app()

#### `model_helpers.R`
Reserved; currently empty. Placeholder for future model-level helper functions.

---

### Name Sanitization

#### `sanitize.R`
Converts parameter names to valid R list element keys.

**Functions:**
- `sanitize_key(name)` [exported] - Converts parameter name to safe R identifier:
  - Lowercase
  - Replace spaces with underscores
  - Remove non-alphanumeric characters except underscores
  - Ensure uniqueness (append _2, _3 if needed)
  - **Receives:** parameter name (from prep_params)
  - **Returns to:** prep_params() for creating list keys

---

### Display/Rendering

#### `render_inspector_panel.R`
Builds the object inspector display (Panel 2) with two sections: inline reference paths (top) and data preview table (bottom).

**Top-Level Functions:**
- `render_inspector_content(data)` - Dispatcher:
  - Routes to appropriate renderer based on `data$type`
  - Calls: `render_model_inspector()`, `render_dataframe_inspector()`, `render_list_inspector()`, etc.
  - **Receives:** `inspector_data()` from app_server
  - **Returns to:** `output$inspector_content` in app_server

**Model Inspector (parameters_model):**
- `render_model_inspector(data)` - Main renderer for model parameters:
  - Checks if `data$params_list` is null (error state)
  - Extracts `params_list` and `list_name`
  - Creates "Inline reference paths" section:
    - Loops through `names(params_list)` (parameter keys like "intercept", "txtreatment")
    - For each parameter, creates chips for each field (median, ci, pd, etc.)
    - Skips parameter1 and parameter2 columns (used for key generation, not display)
    - Chips call `build_field_paths()` to generate copy paths
    - Handles numeric column names (like "95_ci") with `[[]]` syntax
  - Creates "Model parameters" section: calls `render_model_list_table(params_list)`
  - **Receives:** inspector_data from app_server
  - **Returns:** shiny div with split layout

- `build_field_paths(key, list_name)` - Generates base path for inline references:
  - Returns: `"results$intercept$"` (with trailing $)
  - Used by value_chip to create full copy paths
  - **Returns to:** render_model_inspector

- `render_model_list_table(obj)` - Renders parameter summary table:
  - Dynamically uses available columns from list
  - Creates Parameter | column1 | column2 | ... table
  - **Receives:** params_list from render_model_inspector
  - **Returns:** HTML table

**Data Inspector (dataframe):**
- `render_dataframe_inspector(data)` - Renderer for dataframe summaries:
  - Mode toggle: "summary" or "raw"
  - Summary mode: shows column stats with chips (mean, sd, n for continuous; n and per-level pct for categorical)
  - Raw mode: shows raw column access paths
  - Calls `render_data_list_table()` for bottom preview
  - **Returns:** split layout with chips and table

- `render_summary_chips(summary, base)` - Creates chips for individual data columns
- `render_raw_columns_table(raw_df)` - Displays raw column info

**Generic List Inspector:**
- `render_list_inspector(data)` - Handles pre-computed lists:
  - Detects subtype (model_list, data_list, generic)
  - Calls appropriate chip and table renderers

**Shared Functions:**
- `value_chip(label, value, path)` - Renders copyable value chip:
  - Shows: label | formatted value | copy icon
  - Copy button has `data-clipboard` attribute with `{path}` wrapped for inline syntax
  - **Returns to:** all inspector renderers

- `render_inspector_controls(nm, type)` - Renders header controls (mode toggle for dataframes)
- `render_unsupported()` - Error message for unsupported types

---

#### `render_env_panel.R`
Builds the left sidebar showing environment objects.

**Functions:**
- `render_object_list(objs, selected_nm)` - Main renderer for left panel:
  - Filters to only: parameters_model, dataframe, scalar (hides lists, other)
  - Sorts by type: parameters_model first, then dataframe, then scalar
  - Creates clickable rows for each object with type badges and metadata
  - Highlights currently selected object
  - **Receives:** data.frame from `env_objects()` and selected object name
  - **Returns to:** `output$env_object_list` in app_server

---

#### `render_editor_panel.R`
Builds Panel 3 (text editor + live preview + setup chunk button).

**Functions:**
- `render_editor_panel_body()` - Main editor panel:
  - Text input area (`input$editor_text`)
  - Settings toggle button for delimiter choice
  - Live preview area (`output$editor_preview`)
  - Hidden field for converted text (`output$rmd_text`)
  - Setup chunk copy button footer (`output$setup_chunk_ui`)
  - **Returns to:** app_ui as panel content

---

### Expression Rendering

#### `inline_render.R`
Evaluates inline expressions and renders them with styled HTML in the live preview.

**Functions:**
- `render_inline(text, env, delimiter_key)` [exported] - Main preview renderer:
  - Splits text into plain prose and expressions
  - HTML-escapes prose to prevent XSS
  - Evaluates each expression in provided environment
  - Returns styled HTML with values or error messages
  - **Receives:** editor text, render_env, delimiter from app_server
  - **Returns to:** `output$editor_preview` in app_server

- `render_expression(expr_str, env)` - Evaluates single expression:
  - Parses and evaluates in given environment
  - Collapses multi-element vectors with comma separation
  - Renders as `<span class="inline-value">` for success
  - Renders as `<span class="inline-error">` for errors
  - **Called by:** render_inline

- `make_error_span(expr_str, message)` - Creates error span with tooltip
- `newlines_to_br(x)` - Converts newlines to `<br>` tags

- `convert_to_rmd(text, delimiter_key)` [exported] - Converts inline syntax to R Markdown:
  - Converts `{expr}` to `` `r expr` ``
  - Preserves already-correct `` `r expr` `` syntax
  - **Receives:** editor text and delimiter choice
  - **Returns to:** full_chunk() in app_server for copying

---

### Delimiter Configuration

#### `delimiters.R`
Manages different inline expression syntax options (curly braces vs backtick-r).

**Functions:**
- `get_delimiter(key)` - Returns delimiter configuration:
  - Key can be: "{}", "`r`", "$...$", etc.
  - Returns list with: pattern, extract(), to_inline() functions
  - **Receives:** delimiter_key from user settings
  - **Returns to:** render_inline, convert_to_rmd, app_server

---

## Data Flow Diagram

```
USER SELECTS OBJECT (left panel)
  ↓
selected_object(nm) updated
  ↓
inspector_data() reactive fires
  ├─ get(nm, envir=get_session_env()) → retrieve object
  ├─ classify_object(obj) → determine type
  └─ If parameters_model:
     ├─ prep_params(obj) → format & convert to list
     ├─ generate_setup_code(nm, list_name)
     └─ Return: type, params_list, setup_code, list_name
  └─ If dataframe:
     ├─ prep_data(obj) → summarize
     ├─ generate_data_setup_code(nm, list_name)
     └─ Return: type, summary_list, setup_code, list_name
  ↓
observeEvent(inspector_data()) fires
  ├─ assign(list_name, params_list, envir=render_env)
  └─ Now render_env$results_m_lm = formatted list
  ↓
output$inspector_content updated
  └─ render_inspector_content(inspector_data())
     └─ render_model_inspector(data) or render_dataframe_inspector(data)
        └─ Displays: inline reference paths (top) + table (bottom)
  ↓
USER TYPES IN EDITOR
  ↓
input$editor_text updated
  ├─ editor_text_d() debounced 300ms
  │  ↓
  │  output$editor_preview updated
  │  └─ render_inline(text, render_env, delim)
  │     └─ Evaluates expressions against render_env
  │        └─ Shows live preview with styled values
  │
  └─ output$rmd_text updated
     └─ convert_to_rmd(text, delim)
        └─ Converts {expr} to `r expr`
  ↓
USER CLICKS COPY CHUNK BUTTON
  ↓
full_chunk() reactive fires
  ├─ Get editor text
  ├─ Get all environment objects (parameters_model + dataframe)
  ├─ For each object:
  │  ├─ Generate suggested list_name via suggest_list_name()
  │  ├─ Check if list_name appears in editor text
  │  ├─ If yes: generate setup code (generate_setup_code or generate_data_setup_code)
  │  └─ Collect all setup codes
  └─ Return complete chunk: ```{r}\nsetup_codes\n```
     ↓
     User pastes into .qmd, can then copy individual inline code snippets
```

---

## CSS & JavaScript

- **inst/www/styles.css** - All styling for three-panel layout, panels, tables, chips, etc.
  - CSS variables: `--panel-header-height` for consistent header sizing
  - bslib overrides to minimize padding/margins

- **inst/www/clipboard.js** - Handles copy-to-clipboard functionality
  - Reads `data-clipboard` attribute from buttons
  - Copies value to user's clipboard on click

---

## Key Design Decisions

1. **Separate Data Computation from Display**: `inspector_data()` reactive computes, `render_*` functions display
2. **render_env Persistence**: Lists assigned to `render_env` stay available for all subsequent inline references
3. **Formatting at Input**: `prep_params()` and `prep_data()` do all formatting upfront, so renderers receive clean data
4. **Dynamic Table Columns**: `render_model_list_table()` adapts to whatever columns are present
5. **Naming Conventions**: `suggest_list_name()` ensures predictable variable names for users
6. **Word Boundary Matching**: `extract_referenced_names()` uses `\b` to find exact object names in text
7. **Full Chunk Generation**: Instead of separate setup and inline buttons, one button copies a complete, paste-ready .qmd chunk
