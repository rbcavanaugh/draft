# draft

[![R-CMD-check](https://github.com/rbcavanaugh/draft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/rbcavanaugh/draft/actions/workflows/R-CMD-check.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)

**draft** is an R package that launches a local Shiny app to help you write traceable
inline results in R Markdown and Quarto documents. It reads live objects from your
current R session: models, data frames, and single values: and gives you:

- A browsable view of model parameters and data summaries
- Copyable inline reference paths (e.g. `{params_$wt$estimate}`)
- A live-rendering text editor where you type prose and see actual values
- A one-click setup chunk to paste into your `.qmd` or `.Rmd` file

The app does **not** write to your document or interpret results.
You still have to do the thinking; draft removes the friction. When combined 
with automatic table creation (e.g., https://gist.github.com/rbcavanaugh/be76e983fdf3a1920fe1f354d73a5a78)
your results section should be built entirely from your R objects and not manually
created. 

---

## Installation

```r
# Install from GitHub
remotes::install_github("rbcavanaugh/draft")
```

---

## Quick start

```r
library(draft)

# 1. Run your analysis in the normal way
m1     <- lm(mpg ~ wt + cyl, data = mtcars)
params <- parameters::model_parameters(m1)

# 2. Launch the app: it reads everything in your global environment
launch_app()
```

In the app:

1. **Environment panel (left)**: click `params` to inspect it
2. **Object inspector (center)**: see formatted parameter estimates with copyable values
3. **Text editor (right)**: write prose like:

   ```
   Weight was negatively associated with fuel economy
   (b = {params_$wt$estimate}, 95% CI {params_$wt$ci},
   p = {params_$wt$p}).
   ```

   The app suggests `params_` as the list name (object name + trailing underscore).

4. Click **Copy inline code**: the copied text uses `` `r expr` `` syntax, ready to
   paste into your `.qmd` or `.Rmd`.
5. Click **Copy setup chunk**: copies the `prep_params()` call to put in your
   document's setup chunk.

> **Always re-render your full document to confirm results are reproducible.**

---

## Standalone helpers

You can also use these functions directly in a `.qmd` setup chunk without launching the
app:

### Model parameters: prep_params()

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
(Bayesian). Works with any model class supported by `parameters::model_parameters()`,
including correlation matrices.

### Data frame summaries: prep_data()

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

### Marginal means and contrasts: prep_modelbased()

Converts `estimate_means`, `estimate_contrasts`, or `estimate_slopes` objects from
the `modelbased` package:

```r
means_ <- draft::prep_modelbased(modelbased::estimate_means(m1, "cyl"))
# `r means_$x4$mean`, `r means_$x6$mean`, `r means_$x8$mean`
```

### Model performance: prep_performance()

Converts `model_performance` or `compare_performance` output from the `performance`
package:

```r
perf_ <- draft::prep_performance(performance::model_performance(m1))
# R2 = `r perf_$r2`, RMSE = `r perf_$rmse`

comp_ <- draft::prep_performance(performance::compare_performance(m1, m2))
# `r comp_$m1$aic` vs `r comp_$m2$aic`
```

### Effect sizes: prep_effectsize()

Converts an `effectsize_table` object (e.g. `cohens_d()`, `eta_squared()`, `cramers_v()`) into a named list:

```r
es_ <- draft::prep_effectsize(effectsize::cohens_d(mpg ~ am, data = mtcars))
# `r es_$cohens_d`, 95% CI [`r es_$ci_low`, `r es_$ci_high`]

eta_ <- draft::prep_effectsize(effectsize::eta_squared(aov(mpg ~ cyl + gear, mtcars)))
# `r eta_$cyl$eta2`, `r eta_$gear$eta2`
```

Single-effect objects return a flat list; multi-effect objects (e.g. `eta_squared` with
several predictors) return a nested list keyed by the `Parameter` column.

### Distribution summaries: prep_distribution()

Converts `datawizard::describe_distribution()` output into a named list for inline reporting:

```r
dist_ <- draft::prep_distribution(datawizard::describe_distribution(mtcars))
# `r dist_$mpg$mean`, SD = `r dist_$mpg$sd`

# With grouping (by argument):
dist_ <- draft::prep_distribution(datawizard::describe_distribution(iris, by = "Species"))
# `r dist_$setosa$sepal_length$mean`
```

Supports both flat (no `by` argument) and stratified (with `by` argument) shapes.

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
| `insight` | Model detection and value formatting |
| `dplyr` | Data frame manipulation |
| `htmltools` | Safe HTML rendering |
| `effectsize` | Effect size objects (suggested) |
| `datawizard` | Distribution descriptions (suggested) |
| `modelbased` | Marginal means and contrasts (suggested) |
| `performance` | Model performance metrics (suggested) |

---

## Roadmap

### easystats ecosystem support

| Package | Status | Notes |
|---|---|---|
| `parameters` | Supported | Core: all model types with a `parameters_model` class |
| `correlation` | Supported | `correlation()` output inherits `parameters_model` |
| `modelbased` | Supported | `estimate_means()`, `estimate_contrasts()`, `estimate_slopes()` |
| `performance` | Supported | `model_performance()` and `compare_performance()` |
| `effectsize` | Supported | `cohens_d`, `eta_squared`, `cramers_v`, and all `effectsize_table` subclasses |
| `datawizard` | Supported | `describe_distribution()`: flat and stratified (grouped) output |

---

## License

MIT
