# Prepare a modelbased object for inline reporting

Converts estimate_means, estimate_contrasts, or estimate_slopes objects
into a nested named list suitable for inline R Markdown / Quarto
reporting.

## Usage

``` r
prep_modelbased(obj)
```

## Arguments

- obj:

  A modelbased object (estimate_means, estimate_contrasts, or
  estimate_slopes).

## Value

A named list with one element per row. Each element is a named list of
formatted values keyed by lowercased column name.
