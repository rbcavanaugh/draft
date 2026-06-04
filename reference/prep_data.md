# Prepare a data frame for inline reporting

Computes summary statistics for each column and returns a nested named
list suitable for inline R Markdown / Quarto reporting.

## Usage

``` r
prep_data(df, cat_threshold = 10)
```

## Arguments

- df:

  A data frame or tibble.

- cat_threshold:

  Integer. Numeric/integer columns with this many or fewer unique
  non-missing values are treated as categorical. Default 10.

## Value

A named list with one element per column, each containing formatted
summary statistics ready for inline use.
