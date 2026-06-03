# Reproducible Reporting Shiny App — Requirements

## Summary

An R package providing a locally-launched Shiny app that makes it fast and easy to write
traceable inline R Markdown/Quarto reporting text. The app reads live objects from the user's
current R session, exposes their values in a browsable UI, and provides a live-rendering text
editor so the user can write prose with inline R expressions and immediately see the actual
numbers — while copying the raw inline code for pasting into their `.qmd` or `.Rmd` file.

The app does **not** write to the user's document, interpret results, or generate sentences.
The user does the thinking. The app removes the plumbing friction.

---

## Problem Statement

Writing inline R Markdown results (`` `r results$age$estimate` ``) is clunky because:

1. **Variable name hunting** — finding the exact path to a number inside a model object or
   nested list requires trial-and-error in the console.
2. **Long / ugly names** — predictors with spaces, interactions (`age:group`), or random
   effect labels produce unreadable or broken inline references.
3. **Invisible results while writing** — you cannot see the actual rendered number while
   composing prose; you must re-knit the whole document to check.
4. **Multiple model management** — juggling several models, their parameters, and their
   list-path names across a document is error-prone.

---

## Goals

- **G1** — Zero manual results transcription. Every number in a results section should be
  traceable to a live R object.
- **G2** — See actual rendered values while writing prose (before knitting the document).
- **G3** — Copy inline R code (not rendered values) for pasting into `.qmd`/`.Rmd`.
- **G4** — Support any researcher familiar with R; no additional analysis code required
  beyond what they already have.
- **G5** — Distribute as a standard R package (`install.packages()` / GitHub); no hosted
  server needed.

---

## Non-Goals (v1)

- Automated sentence or paragraph generation
- Interpretation or statistical guidance
- Writing directly to the user's `.qmd`/`.Rmd` file
- Hosting or multi-user access
- Table generation (tables are produced in the user's script; this app is for inline text only)
- Support for `.Rmd`/`.qmd` sourcing as the data-access method (planned for v2)

---

## Distribution & Launch

- Delivered as an R package (GitHub initially; CRAN as stretch goal)
- User launches with `draft::launch_app()` (or similar) from the **same R session** where
  their analysis objects live
- The app reads the calling environment via `rlang::caller_env()` / `globalenv()`
- No authentication, no external dependencies beyond CRAN packages
- Target audience: researchers and PhD students familiar with R

---

## Data Access (v1)

The app inspects `globalenv()` at launch and on user-triggered refresh.

### Object classification

| Detected type | Treatment |
|---|---|
| Data frame / tibble | Offer summary statistics mode OR raw column-access mode |
| Model object (has a `model_parameters()` method) | Run `parameters::model_parameters()` |
| Named list | Expose as-is for navigation |
| Other | Show in environment panel but flag as unsupported |

Detection of model objects: attempt `parameters::model_parameters()` in a `tryCatch`; fall
back to raw list access if it fails.

### `model_parameters()` options exposed in UI

For model objects, expose at minimum:
- `effects` selector: `"fixed"` / `"random"` / `"all"`
- A refresh button to re-run with updated options

Keep parameters options minimal in v1; expand in v2.

### Sanitized key names

Every parameter/variable name is sanitized to a clean snake_case key:
- Spaces → `_`
- Remove all punctuation except `_`
- Interaction terms (`A:B`) → `A_x_B`
- Truncate extreme lengths with a deterministic suffix if needed

The UI always shows **both** the original name and the sanitized key side by side.

---

## Three-Panel UI Layout

```
┌──────────────────┬───────────────────────────┬──────────────────────────────┐
│  (1) Environment │  (2) Object Inspector     │  (3) Text Editor + Preview   │
│  Panel           │                           │                              │
│                  │                           │  [ textarea ]                │
│  Objects in      │  Click a parameter row    │                              │
│  globalenv():    │  to see:                  │  Live rendered preview:      │
│                  │  - original name          │  prose with values           │
│  • model1  [M]   │  - sanitized key          │  highlighted in color        │
│  • model2  [M]   │  - current formatted      │                              │
│  • df1     [D]   │    value(s)               │  [ Copy inline code ]        │
│  • ...           │  - full list path         │                              │
│                  │  - click-to-insert        │                              │
└──────────────────┴───────────────────────────┴──────────────────────────────┘
```

Legend: `[M]` = model object, `[D]` = data frame, `[L]` = list

### Panel 1 — Environment

- Lists all objects in `globalenv()` with type badges
- Unsupported types shown greyed out
- "Refresh environment" button
- Click an object to load it in Panel 2

### Panel 2 — Object Inspector

Displays a table of parameters/values for the selected object. Each row shows:

| Column | Content |
|---|---|
| Original name | Raw name from model/data |
| Sanitized key | Clean name for use in list path |
| Value preview | Formatted current value (e.g., `"0.34"`) |
| Full list path | Complete inline reference, e.g., `results$age$estimate` |
| Insert button | Appends the list path to cursor position in Panel 3 (stretch) |

For model objects, sub-tables per `effects` level (fixed / random / all).

For data frames in summary mode, one row per column with descriptive stats cells
(mean, SD, n, %, median as applicable by column type).

For data frames in raw mode, one row per column with `df$colname` path.

The generated list object (e.g., `results <- model_parameters(model1) |> ...`) is shown
as a copyable code block so the user can source it at the top of their document.

### Panel 3 — Text Editor & Live Preview

**Editor**: Plain `textarea` (v1). ShinyAce with markdown mode considered for v2.

**Inline expression syntax**: Users wrap expressions in a delimiter rather than typing
raw `` `r expr` `` syntax. A settings panel (gear icon or collapsible box) lets users
choose their preferred delimiter:

| Option | Example | Default |
|---|---|---|
| `{expr}` | `{results$age$estimate}` | ✓ |
| `{{expr}}` | `{{results$age$estimate}}` | |
| `` `r expr` `` | `` `r results$age$estimate` `` | |

The selected delimiter is stored in the session. On copy, all delimiters are converted
to `` `r expr` `` format for pasting into `.qmd`/`.Rmd`.

**Live preview**: A reactive HTML panel below the textarea that:
1. Parses all delimited expressions using the currently selected syntax
2. Evaluates each expression in a sandboxed environment that has access to the
   constructed list objects
3. Replaces each expression with the rendered value wrapped in an HTML `<span>`,
   styled as a grey pill (e.g., `background: #e8e8e8; color: #c0392b; border-radius: 3px`)
4. Renders surrounding prose as plain text (no full Markdown rendering in v1)
5. Updates reactively on every keystroke (debounced ~300ms)

**Copy button**: Copies the raw textarea content with all delimiters converted to
`` `r expr` `` syntax — never the rendered HTML values.

**Error handling**: If an expression fails to evaluate, show it in red with the error
message as a tooltip rather than crashing the preview.

---

## List Construction

The app constructs named lists from objects so inline references are short and readable.

### Model objects

```r
# Generated by the app; user pastes this into their .qmd setup chunk
results_model1 <- parameters::model_parameters(model1) |>
  as.data.frame() |>
  split_to_list()   # internal helper: splits rows into named sub-lists by sanitized key
```

Each parameter becomes a sub-list with fields:
- `estimate` — formatted point estimate
- `ci_low` — lower confidence/credible interval bound
- `ci_high` — upper bound  
- `ci` — formatted interval string, e.g., `"[0.12, 0.56]"`
- `p` — p-value (frequentist) or `pd` / `rope_pct` (Bayesian) as applicable
- `se` — standard error (if available)

Fields are kept separate so the user controls the narrative (writes `"B = "` or `"OR = "`
themselves).

### Data frame summary mode

```r
stats_df1 <- draft::prep_data(df1)  # exported — usable in .qmd setup chunks
```

Continuous columns: `mean`, `sd`, `median`, `min`, `max`, `n`  
Categorical columns: per-level `n` and `pct`

### Data frame raw mode

No transformation; user references `df1$colname` directly.

---

## Formatting

- All numbers formatted via `parameters::format_value()` or equivalent (consistent with
  `model_parameters()` output)
- Default: 2 decimal places for estimates, 3 for p-values
- v1: fixed formatting; v2 may expose format options in UI
- APA-style p-value display (e.g., `< .001` not `0.000`)

---

## Recommended User Workflow

1. Open `.qmd`/`.Rmd`, run all chunks so objects are in `globalenv()`
2. Call `draft::launch_app()`
3. In Panel 1, select objects to work with
4. In Panel 2, browse parameters and note list paths
5. Copy the generated list-construction code block into a setup chunk in the document
6. In Panel 3, write prose; see live rendered values; copy raw inline code
7. Paste inline code into the `.qmd`/`.Rmd`
8. Re-render the full document from scratch to confirm reproducibility

The app displays a persistent reminder: *"Always re-render your full document to confirm
results are reproducible."*

---

## Package Architecture

Follows the golem convention (without using golem as a dependency): all R logic lives in
`R/` as named functions; static assets in `inst/www/`; no `inst/app/` directory.

```
draft/
  R/
    launch_app.R              # launch_app(), get_session_env()
    app_ui.R                  # app_ui() — top-level UI function
    app_server.R              # app_server() — top-level server function
    classify_objects.R        # list_objects(), classify_object()
    render_env_panel.R        # Panel 1 UI rendering helpers
    render_inspector_panel.R  # Panel 2 UI rendering helpers
    render_editor_panel.R     # Panel 3 UI rendering helpers
    sanitize.R                # sanitize_key() — internal
    model_helpers.R           # reserved (currently empty)
    precompute_models.R       # precompute_model_params() — internal
    prep_model.R              # prep_params() — EXPORTED
    prep_data.R               # prep_data() — EXPORTED, raw_columns()
    code_generator.R          # generate_setup_code()
    inline_render.R           # render_inline()
    delimiters.R              # delimiter definitions + copy conversion
  inst/
    www/
      styles.css              # app CSS; loaded via addResourcePath()
      clipboard.js            # copy-to-clipboard JS
  DESCRIPTION
  NAMESPACE
```

Key dependencies: `shiny`, `bslib`, `parameters` (easystats), `insight` (easystats),
`dplyr`, `htmltools`

### Code style

- Many small, single-responsibility `R/` files — one concern per file
- `app_server.R` stays minimal; delegates to render helpers and fct helpers
- Block comment at the top of each function describing purpose and approach;
  line-by-line comments added only when fixing bugs or handling non-obvious edge cases
- No unit tests in v1

---

## Exported User-Facing Functions

Beyond `launch_app()`, several functions are useful standalone — users may want to call
them directly in a `.qmd` setup chunk without launching the app.

### `prep_params(params_obj)` — **exported**

The most important standalone function. Accepts a `parameters_model` object (the output
of `parameters::model_parameters()`) and returns a named list keyed by sanitized
parameter names, where each element is itself a list of formatted values. Users paste
the generated setup code into their document and reference values directly.

```r
# In a .qmd setup chunk:
params_m1 <- parameters::model_parameters(my_model)
results   <- draft::prep_params(params_m1)

# Then inline:
# Age was associated with outcome ({results$age$estimate},
# 95% CI {results$age$ci}, p = {results$age$p})
```

Each parameter sub-list contains all non-NA formatted columns from
`parameters::model_parameters()`, which typically includes: `estimate`, `se`, `ci`,
`ci_low`, `ci_high`, `p` (frequentist) or `pd`, `rope_pct` (Bayesian).

### `prep_data(df)` — **exported**

Produces a named list of descriptive statistics from a data frame, keyed by column
name. Continuous columns: `mean`, `sd`, `median`, `min`, `max`, `n`. Categorical
columns: per-level `n` and `pct`. Useful in setup chunks for demographics reporting.

```r
stats <- draft::prep_data(demo_data)
# Age: M = {stats$age$mean} (SD = {stats$age$sd})
# Female: {stats$sex$female$pct}%
```

### Internal-only (not exported)

`list_objects()`, `classify_object()`, `render_*()`, `render_inline()`,
`get_session_env()`, `generate_setup_code()` — app infrastructure, not intended for
direct use.

`sanitize_key()` converts raw parameter/column names to valid R list keys: lowercases,
replaces spaces and non-alphanumeric characters with underscores, strips leading/trailing
underscores, and appends numeric suffixes (`_2`, `_3`) to deduplicate. Not exported.

---

## v2 / Future Scope

- Source `.qmd`/`.Rmd` file to populate environment (no live session required)
- ShinyAce editor with markdown syntax highlighting
- Expose more `model_parameters()` options (standardize, exponentiate, etc.)
- `performance` package metrics (R², ICC, model comparison) as additional inline values
- Format options (decimal places, CI style) in UI
- Multi-document / project session saving
- CRAN submission

---

## Open Questions

- **Sandboxing**: How strictly should inline expression evaluation be sandboxed? Should
  arbitrary R be allowed or only pre-approved list paths?
- **Brms / Bayesian fields**: Confirm exact field names from `model_parameters()` for
  `brmsfit` objects (pd, rope_pct, etc.) to ensure list construction covers them.
- **Refresh on environment change**: Should the app auto-detect new objects or require
  manual refresh? (Manual is safer for v1.)
- **Session persistence**: Should the text editor content persist across app restarts
  within a session? (Could use `tempfile()` write on change.)
