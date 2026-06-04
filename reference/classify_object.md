# Classify an object into a draft type string

Walks the handler registry in priority order and returns the type string
of the first matching handler. Falls back to `"scalar"`, `"list"`, or
`"other"` for objects not covered by any registered handler.

## Usage

``` r
classify_object(obj)
```

## Arguments

- obj:

  Any R object.

## Value

A single character string: a registered handler type (e.g.
`"parameters_model"`, `"dataframe"`) or `"scalar"`, `"list"`, `"other"`.
