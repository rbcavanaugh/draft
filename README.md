# draft

**draft** is an R package that launches a local Shiny app to help you write traceable
inline results in R Markdown and Quarto documents. It reads live objects from your
current R session — models, data frames, and single values — and gives you:

- A browsable view of model parameters and data summaries
- Copyable inline reference paths (e.g. `{results_m1$age$estimate}`)
- A live-rendering text editor where you type prose and see actual values
- A one-click setup chunk to paste into your `.qmd` or `.Rmd` file

The app does **not** write to your document or interpret results. You do the thinking;
draft removes the plumbing friction.

---

## Installation

```r
# Install from GitHub
remotes::install_github("rbcavanaugh/reproducible-reporting")
```

---

## Quick start

```r
library(draft)

# 1. Run your analysis in the normal way
m1     <- lm(mpg ~ wt + cyl, data = mtcars)
params <- parameters::model_parameters(m1)

# 2. Launch the app — it reads everything in your global environment
launch_app()
```

In the app:

1. **Environment panel (left)** — click `params` to inspect it
2. **Object inspector (centre)** — see formatted parameter estimates with copy chips
3. **Text editor (right)** — write prose like:

   ```
   Weight was negatively associated with fuel economy
   (b = {results_params$wt$estimate}, 95% CI {results_params$wt$ci},
   p = {results_params$wt$p}).
   ```

4. Click **Copy inline code** — the copied text uses `` `r expr` `` syntax, ready to
   paste into your `.qmd` or `.Rmd`.
5. Click **Copy setup chunk** — copies the `library` + `prep_params()` call to put in
   your document's setup chunk.

> **Always re-render your full document to confirm results are reproducible.**

---

## Standalone helpers

You can also use these functions directly in a `.qmd` setup chunk without launching the
app:

### `prep_params(params_obj)`

Converts a `parameters_model` object into a nested named list for inline reporting:

```r
# Setup chunk
params_m1 <- parameters::model_parameters(m1)
results   <- draft::prep_params(params_m1)

# Inline usage
# Weight: b = `r results$wt$estimate` (95% CI `r results$wt$ci`, p = `r results$wt$p`)
```

Each parameter is a sub-list containing all available formatted fields:
`estimate`, `se`, `ci`, `ci_low`, `ci_high`, `p` (frequentist) or `pd`, `rope_pct`
(Bayesian).

### `prep_data(df)`

Summarises a data frame into a nested named list for demographics reporting:

```r
# Setup chunk
stats <- draft::prep_data(demo_data)

# Inline usage
# Age: M = `r stats$age$mean` (SD = `r stats$age$sd`)
# Female: `r stats$sex$female$pct`%
```

Continuous columns return `mean`, `sd`, `median`, `min`, `max`, `n`, `n_missing`.
Categorical columns return `n`, `n_missing`, and per-level `n` and `pct`.

---

## Recommended workflow

1. Open your `.qmd` / `.Rmd` and run all chunks so objects are in `globalenv()`
2. Call `draft::launch_app()`
3. Browse parameters in the inspector; note list paths
4. Write prose in the text editor; see live-rendered values
5. Copy the setup chunk into your document's setup block
6. Copy inline code and paste into your document
7. Re-render the full document to confirm reproducibility

---

## Dependencies

| Package | Purpose |
|---|---|
| `shiny` | App framework |
| `bslib` | UI layout |
| `parameters` | `model_parameters()` and value formatting |
| `insight` | Model detection |
| `dplyr` | Data frame manipulation |
| `htmltools` | Safe HTML rendering |

---

## Roadmap

### easystats ecosystem support

| Package | Status | Notes |
|---|---|---|
| `parameters` | Supported | Core — all model types with a `parameters_model` class |
| `correlation` | Supported | `correlation()` output inherits `parameters_model` |
| `modelbased` | Planned | `estimate_means()`, `estimate_contrasts()`, `estimate_slopes()` need a custom inspector |
| `effectsize` | Planned | `effectsize_table` class needs a custom inspector |
| `performance` | Planned | `model_performance()` and `compare_performance()` need a custom inspector |

---

## License

MIT
