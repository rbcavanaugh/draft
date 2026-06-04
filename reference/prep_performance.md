# Prepare a performance object for inline reporting

Converts model_performance or compare_performance objects into a named
list suitable for inline R Markdown / Quarto reporting.

## Usage

``` r
prep_performance(obj)
```

## Arguments

- obj:

  A performance object (output of model_performance() or
  compare_performance()).

## Value

For model_performance: a flat named list of formatted metric values. For
compare_performance: a nested named list keyed by model name.
