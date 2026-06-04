# Build Plan — Reproducible Reporting Shiny App

## Guiding principles

- Each stage produces a working, runnable artifact — no half-built state
- Stages are sized to fit within a single Claude session (~2-4 files touched per stage)
- Each stage ends with a clear verification step
- Later stages build on earlier ones without requiring rewrites
- Many small, focused `R/` files — one concern per file; `server.R` delegates to helpers and stays minimal
- No unit tests — skip `tests/` scaffolding unless explicitly requested

---

## Stage 1 — Package scaffold + environment inspection

**Goal**: A launchable (but empty) Shiny app that reads `globalenv()` and lists objects
with type badges. No UI polish, no model processing yet.

**Files created/touched**:
- `DESCRIPTION`
- `NAMESPACE`
- `R/launch_app.R` — `launch_app()` entry point, captures env
- `R/classify_objects.R` — `list_objects()`, `classify_object()` (model / data frame / list / other)
- `inst/app/app.R` — minimal Shiny skeleton, Panel 1 only

**Verification**: Call `launch_app()` from a session with a few objects; see them listed
with correct type badges.

---

## Stage 2 — Name sanitization + model_parameters() wrapper

**Goal**: Given a model object, run `model_parameters()` and return a tidy data frame with
original names, sanitized keys, and formatted values. No UI yet — pure R logic.

**Files created/touched**:
- `R/sanitize.R` — `sanitize_key()`: wraps `janitor::make_clean_names()`, adds `:`→`_x_`
  for interaction terms; internal only
- `R/model_helpers.R` — `get_model_params(model, effects)`: wraps `model_parameters()`,
  attaches sanitized keys, returns tidy data frame

**Verification**: Run `get_model_params(lm(mpg ~ wt + cyl, mtcars))` and inspect output.

---

## Stage 3 — Data frame summary helper

**Goal**: Given a data frame, produce a tidy summary suitable for inline reporting
(continuous: mean/sd/median/n; categorical: n/pct per level). Pure R logic, no UI.

**Files created/touched**:
- `R/prep_data.R` — `prep_data(df)` (exported), `raw_columns(df)` (internal)

**Verification**: Run `prep_data(mtcars)` and check output structure.

---

## Stage 4 — List construction + generated code block

**Goal**: Convert model params or data summary into the nested named list that users
will `source()` at the top of their document. Also generate the copyable R code string.

**Files created/touched**:
- `R/prep_model.R` — `prep_model(model, effects)` (exported): full pipeline from model
  object to named list with `estimate`, `ci_low`, `ci_high`, `ci`, `p`, `se` sub-keys
- `R/code_generator.R` — `generate_setup_code(obj_name, list_name, effects)`: returns
  character string of R code for user's setup chunk (internal)

**Verification**: Confirm list structure and that generated code string is valid R that
re-creates the list when `eval(parse(...))`'d.

---

## Stage 5 — Inline expression renderer

**Goal**: Given a text string with `{expr}` (or other delimiter) patterns and an
environment, return an HTML string with expressions replaced by styled `<span>` values.
This is the core of the live preview feature. Pure R logic, no UI yet.

**Files created/touched**:
- `R/inline_render.R` — `render_inline(text, env, delimiter)`: regex parse → evaluate →
  HTML substitution with error handling
- `R/delimiters.R` — `delimiters` list (patterns + copy-conversion functions for each option)

**Verification**: `render_inline("Age was {results$age$estimate}", env, "{}")` returns
correct HTML with styled span.

---

## Stage 6 — Wire up Panel 2 (Object Inspector)

**Goal**: Clicking an object in Panel 1 populates Panel 2 with the parameter/summary
table. Effects selector for models. Raw vs. summary toggle for data frames. Copyable
setup code block.

**Files created/touched**:
- `inst/app/app.R` — add Panel 2 server logic, connect to `get_model_params()` /
  `prep_data()` / `raw_columns()`
- `inst/app/ui.R` (split out from app.R if it has grown large)

**Verification**: Load a session with `lm`, `lme4::lmer`, and a data frame; click each;
confirm tables render correctly with all columns.

---

## Stage 7 — Wire up Panel 3 (Text Editor + Live Preview)

**Goal**: Textarea + live rendered preview panel. Settings box for delimiter choice.
Copy button that converts to `` `r expr` `` syntax.

**Files created/touched**:
- `inst/app/app.R` (or `server.R`) — Panel 3 server logic, reactive inline renderer,
  clipboard JS handler
- `inst/app/www/styles.css` — `.inline-value`, `.inline-error` span styles
- `inst/app/www/clipboard.js` — copy-to-clipboard with delimiter conversion

**Verification**: Type prose with `{results$age$estimate}` in the editor; confirm preview
shows rendered value in styled span; confirm copy gives `` `r results$age$estimate` ``.

---

## Stage 8 — Integration pass + UX polish

**Goal**: End-to-end test of full workflow. Add the persistent re-render reminder.
Fix any panel wiring issues. Ensure environment refresh works.

**Files created/touched**:
- `inst/app/app.R` / `ui.R` / `server.R` — refresh button logic, reminder banner,
  layout fixes
- `R/launch_app.R` — confirm env capture is robust across RStudio / positron / terminal

**Verification**: Full workflow from a real `.qmd` session: load objects, build list,
write prose, copy, paste into document, re-render document successfully.

---

## Stage 9 — Documentation + package finalization ✓ complete

**Goal**: Package is installable from GitHub, has a README, and passes `R CMD check`.

**Files created/touched**:
- `README.md` — install instructions, 5-minute quickstart, all exported helpers documented
- `man/` — roxygen docs for all exported functions
- `DESCRIPTION` — finalized dependencies, version, license
- `APP_DOCUMENTATION.md` — full architecture reference for the handler registry pattern

**Verification**: Fresh install from GitHub, `launch_app()` works, `R CMD check` passes
with no errors.

---

## Dependency budget (keep lean)

| Package | Purpose |
|---|---|
| `shiny` | App framework |
| `parameters` | `model_parameters()`, `format_value()` |
| `insight` | Model detection, `is_model()` |
| `rlang` | Environment capture |
| `dplyr` | Data frame manipulation |
| `stringr` | Name sanitization |

Avoid heavy dependencies (tidymodels, gt, flextable, etc.) — those belong in the user's
own script.

---

## Session size notes

- Stages 1–4 are pure R logic with no Shiny wiring — safe to do in one session each
- Stage 5 (inline renderer) is the most self-contained and testable unit; keep it isolated
- Stages 6–7 touch `app.R` heavily — if the file grows large, split into `ui.R` +
  `server.R` + `modules/` before starting Stage 6
- Stage 8 should be a short session; if major issues surface, open a new focused session
  per issue
- Never combine a "add feature" stage with a "refactor structure" stage in the same session
