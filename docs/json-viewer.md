# JSON viewer

Two commands, both in `~/.local/bin`:

| Command       | What it does                                                          |
| ------------- | --------------------------------------------------------------------- |
| `json-view`   | fzf picker over every JSON file under a directory, with a live preview |
| `json-pretty` | the renderer behind it — usable on its own, and in a pipe              |

```sh
json-view                 # every .json/.jsonl/.ndjson/.geojson below $PWD
json-view logs/           # …below a directory
json-view one.json        # one file: straight to the full-screen view
json-view --code .        # ctrl-o hands files to VS Code instead of $EDITOR
curl -s "$url" | json-view
```

Inside the picker: `enter` opens the full-screen view and comes back to the list
when you quit it, `ctrl-o` opens the file in `$EDITOR`, `ctrl-r` switches the
preview to raw JSON (bat) and `ctrl-p` switches it back, `ctrl-y` copies the
path, `ctrl-/` hides the preview.

The same rendering is wired into the file managers, so a JSON file previews this
way in yazi (`plugins/json-preview.yazi`) and in lf (`.config/lf/preview.sh`)
too.

## What it does to the JSON

`jq .` already indents. What makes real JSON unreadable is the *inside* of the
strings, and that is what this fixes.

**Escaped newlines become real lines.** A stack trace stored as one string is
printed as a block: opening quote on the key's line, content indented under it,
closing quote lined back up with the key. A dim rail down the left marks how far
the value extends.

```
  "message": "
  │ Traceback (most recent call last):⏎
  │   File "/srv/app/checkout.py", line 412, in charge⏎
  │     resp = gateway.charge(order, card)⏎
  │ ValueError: card declined (code=51)
  ",
```

The `⏎` means *there was a `\n` here*. A line that wraps because it was too wide
for the pane has no glyph, so the two can always be told apart.

**JSON inside a string is expanded** and tagged `⟨json⟩`, instead of arriving as
a blob of backslash-escaped quotes:

```
  "payload": " ⟨json⟩
  │ {
  │   "order_id": "A-9912",
  │   "items": [
  │     { "sku": "tee-blk-m", "qty": 2 }
  │   ]
  │ }
  ",
```

Only objects and arrays are expanded. The string `"123"` stays a string — the
viewer never repaints a value as something it is not.

**Long values wrap** to the pane width instead of running off the right edge,
and the wrap accounts for double-width characters.

**Nothing is silently rewritten.** Numbers print as the text the file contained
(`1.50` stays `1.50`, a 30-digit integer stays exact), duplicate keys are both
shown, key order is the file's order. A file that is not valid JSON is not an
error to hide: the parse error is reported with a caret under the offending
column, then the file is printed unparsed.

Rails are drawn only around expanded strings, never per nesting level — braces
already show structure, and a rail per level turns deep JSON into a picket fence.

## json-pretty on its own

```sh
json-pretty file.json                  # renders; colour when stdout is a tty
json-pretty -n file.json               # line-number gutter
json-pretty *.json                     # headers naming each file
json-pretty --width 80 file.json       # fixed width instead of the terminal's
json-pretty --raw-strings file.json    # leave strings escaped
json-pretty --no-embedded file.json    # don't expand JSON found in strings
json-pretty --plain --raw-strings f.json | jq .   # valid JSON out
```

`--plain` drops the rails, glyphs and record rules; together with
`--raw-strings` the output is valid JSON and round-trips, which is what the
tests assert. `--max-rows N` stops early — the fzf preview uses it so a huge
file cannot make cursor movement expensive.

JSON Lines and concatenated documents are detected automatically and separated
by a dim `── record N` rule.

## Colours

Tokens use Visual Studio Dark+ — the same theme as `BAT_THEME`, so a JSON file
looks the same here as in bat, delta, VS Code and the yazi preview. The chrome
(rails, glyphs, headers, line numbers) uses Tokyo Night night, like every other
TUI here. Both palettes are in [`docs/tokyonight.md`](tokyonight.md).

`--color never`, a non-tty stdout, or `NO_COLOR` in the environment turns colour
off.

## Requirements

`python3` for `json-pretty`; `fzf` for the picker (a single file or stdin does
not need it); `bat` for the raw preview toggle and `less` for paging, both
optional; `fd` is used to find files when present, otherwise `find`.

Tests: `python3 -m unittest tests.test_json_pretty`.
