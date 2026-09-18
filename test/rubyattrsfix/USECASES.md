# Ruby attribute semantics — runtime-verified behaviour map

Every `proven` row below was verified by executing this exact code against a running Rails
application (ActiveRecord + ActiveModel at runtime); the run was repeated and produced
byte-identical results. `static-pinned` rows are static-index expectations pinned by
`test/rubyattrscheck.sh` — they name what the indexer must do, not what Ruby must be.
Fixture files are the ones beside this document.

## Collision matrix arms (canonical name `name`)

| Arm | Fixture | Status |
|---|---|---|
| single: attr only | single_attr.rb | proven |
| pair (def, attr) — attr after def | pair_def_attr.rb | proven: attr reader wins (same-class last-def-wins) |
| pair (attr, def) — def after attr | pair_attr_def.rb | proven: def reclaims reader; attr writer survives |
| pair (attr, column) | pair_attr_column.rb | proven: ivar wins; mass assignment also shadowed (finding 1) |
| pair (attr, yaml) | attr_yaml.rb + spike_names.yml | proven |

## Setter-binding arms

| Form | Status |
|---|---|
| `attr_reader :name` → no `name=` | proven |
| `attr_writer :name` → `name=` | proven |
| `attr_accessor :name` → `name=` | proven |
| `attribute :name` → `name=` (attribute store) | proven |
| `def name=` → `name=` | proven |

Static binding of `record.name = v` to the `name=` def: static-pinned (rubyattrscheck).

## Attr-family form coverage

| Form | Status |
|---|---|
| multi-symbol `attr_accessor :multi_a, :multi_b` | proven (multi_attr.rb) |
| typed `attribute :quantity, :integer, default: 0` — metadata args define nothing | proven (typed_attr.rb; `respond_to?(:integer)` is false) |
| plural `attributes :x, :y` | **MEASURED FLOOR — no class-level plural exists** in base Rails/ActiveModel (NoMethodError at runtime). Static capture stays as third-party-DSL forward-compat only. |
| `attributes :block_a do … end` — the do-block body (with its block parameter) defines nothing | static-pinned only; block_attr.rb is never executed (it would raise) — valid syntax so the static walk can prove the block-body guard |

## Measured findings (runtime truth)

1. **`attr_accessor` also shadows AR's attribute store.** mass assignment through the ivar
   writer leaves the column NULL; writing the column requires `record[:name] = ...`.
2. **(def, attr) in one class is order-sensitive** (last definition wins) — unlike
   (def, `attribute`), where the module-generated reader makes it order-insensitive.
   Both orders tested. ripwire's def tower orders DEFS, not runtime method-table
   precedence — disclosed, not a contradiction.
