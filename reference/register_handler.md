# Register a class handler

Register a class handler

## Usage

``` r
register_handler(
  type,
  priority = 100L,
  badge,
  detect,
  class_label,
  size_label,
  context = function(input) list(),
  prep,
  assign_result = function(result) result,
  setup_code,
  controls = function(nm, type) NULL,
  render
)
```
