# List objects in an environment

Returns a data frame describing all user-visible objects in the given
environment. Objects whose names start with "." are excluded.

## Usage

``` r
list_objects(env = globalenv())
```

## Arguments

- env:

  An environment. Defaults to
  [`globalenv()`](https://rdrr.io/r/base/environment.html).

## Value

A data frame with columns: `name`, `type`, `class_label`, `size_label`.
One row per visible object.
