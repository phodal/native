# Native SDK calculator example

A real four-function calculator built to showcase precision Native SDK layout: the classic keypad grid with exact 66x54 keys, a live expression + result display with the last calculation remembered above it, full keyboard input, and a near-monochrome theme with a single calculator-orange accent. The window is fixed at 320x496 — every frame in it is deliberate, and the test suite asserts the keypad's frames to the point.

## Arithmetic model (documented, tested)

**Immediate execution**, the model every desk calculator uses: `2 + 3 × 4 =` is `(2 + 3) × 4 = 20` — each operator applies the one before it, there is no precedence. On top of that:

- Chained operators evaluate live (`2 + 3 ×` shows `5` the moment × lands); pressing a second operator with no operand just switches it.
- `=` repeats: `2 + 3 = = =` walks 5, 8, 11. `5 + =` uses the display as the missing operand (10).
- `%` divides the current operand by 100 (no additive-percent special case — that is the whole rule).
- `±` negates the entry while typing, or the standing value otherwise.
- Backspace edits the number being typed, down to `0` and never past it; results are not editable.
- Division by zero (and any non-finite result, including `0 ÷ 0`) shows **Error** with the failing calculation in the expression line; operators go inert until AC — or any digit, which starts fresh.

All arithmetic is f64 with honest display formatting (`formatValue`): integers print exactly up to 12 digits, fractions round to at most 10 decimals for display only (the model keeps full precision — `0.1 + 0.2` shows `0.3`, continues as the exact sum), and anything beyond the 12-digit window prints in scientific notation. Typed entries cap at 12 significant digits, like the desk calculators the model imitates.

## Keyboard (the seam, documented)

The expression line is a real `text_field` and it is the app's keyboard path: click it (or Tab to it) and digits, `+ - * x / . , % =`, backspace, and enter all flow through the widget keyboard path as `TextInputEvent`s that `update` parses into calculator keys — the field's text is model-derived, so unknown characters can never appear. `c` clears. **Escape is a chrome shortcut** (`native_sdk.Shortcut`, mapped through `on_command`) so AC works with no widget focused at all; unmodified character keys deliberately cannot be chrome shortcuts, which is why the text-entry seam carries them.

## Authoring split (markup-first)

- `src/keypad.zml` — the entire keypad, key by key: function keys `secondary`, the operator column and equals `primary` (the one accent), digits default surfaces, the pending operator highlighted via a model-sourced `selected=`. Markup message payloads are bindings, so each key dispatches its own void `Msg` arm — which also reads exactly like the keypad it is.
- `src/header.zml` — brand label + the theme cycle button (auto → light → dark).
- `src/view.zig` — the one Zig-only section: the display block, because the big result line needs a scaled, right-aligned paragraph (markup text tops out at the `lg` body size). Also documented there: text fields are start-aligned by the engine (caret math), so the expression line stays left-aligned.
- `src/model.zig` — the whole engine and the **plain-form TEA update**: no effects, no timers, no I/O. This is the smallest real Native SDK app shape.
- `src/theme.zig` — graphite + calculator-orange tokens for both modes, high-contrast falling back to the framework palettes, 18px keypad glyphs via `typography.button_size`, and a deeper active-orange for the pending operator via `controls.button_primary.active_background`.

## Run

```sh
zig build run -Dplatform=macos -Dweb-engine=system
```

Click the expression line and type `12+7⏎`, or press the keys. Escape clears from anywhere. The theme button cycles auto/light/dark; auto follows the system appearance live.

Run the deterministic suite (exhaustive arithmetic through `msgForPointer` on every key, keyboard through real `gpu_surface_input` events, the Escape shortcut through the platform event path, formatting, theming, markup engine parity, snapshot assertions, and the exact-frame keypad layout check):

```sh
zig build test -Dplatform=null
```

Verify live through the automation harness:

```sh
zig build -Dplatform=macos -Dweb-engine=system -Dautomation=true
./zig-out/bin/calculator &
native automate assert 'gpu_nonblank=true' 'role=button name="Equals"' 'role=textbox name="Expression"'
# Keyboard rides the focused expression field: focus it (widget-click its
# id from the snapshot), then type 9 × 9 ⏎ and watch the result land.
native automate widget-key calc-canvas 9 9 && native automate widget-key calc-canvas x x && native automate widget-key calc-canvas 9 9 && native automate widget-key calc-canvas enter
native automate assert 'role=text name="81"'
```
