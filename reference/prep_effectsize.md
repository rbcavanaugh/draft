# Prepare an effectsize object for inline reporting

Converts any effectsize_table object into a named list suitable for
inline R Markdown / Quarto reporting. Multi-row objects (e.g.
eta_squared with multiple predictors) are keyed by the Parameter column.
Single-row objects (e.g. cohens_d) are returned as a flat named list.

## Usage

``` r
prep_effectsize(obj)
```

## Arguments

- obj:

  An effectsize object inheriting from effectsize_table.

## Value

A named list of formatted character values (single-row objects) or a
nested named list keyed by parameter name (multi-row objects).
