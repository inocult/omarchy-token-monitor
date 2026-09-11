# omarchy-token-monitor

Tokens, dollars and rate limits for every AI coding subscription you pay for,
across every machine you code on — as a native [Omarchy](https://omarchy.org)
shell plugin.

A bar panel that behaves like the network and bluetooth ones, and the same
dashboard again as either a screen-pinned strip or an ordinary tiled window.

```
$27.01 today                                        ● just now
37,628,315 tokens  ·  2 machines
cost is this machine only

[ By machine ]  By subscription

MACHINES
eye  ·  this one                            182M    $132.67
  ✳ Claude Code  Max 20x
    Session       ▁                            1%    5h
    Weekly        ▄▄▄▄▄                        32%    3d
    Fable Weekly  ▄▄▄                          22%    3d
  ◐ Codex                                not signed in
workshop                                    211k      $0.42
  ✳ Claude Code  Max 5x
    ...
```

## Why it exists

Omarchy already ships `omarchy.agents`, which covers rate limits, tokens by day
and tokens by model, and merges usage across machines. Two things it
deliberately does not do, both for good reasons, and both of which this adds:

- **No cost.** Rates change, and collection is the wrong place for a price
  table. So cost is computed alongside the records instead of inside them.
- **No per-subscription, per-machine view.** Its sync format drops `limits` and
  `tierLabel` on purpose: a rate limit belongs to an *account*, and two machines
  signed into two different Claude accounts have two separate allowances that
  must not be merged. This carries them per machine and only ever shows them
  side by side.

## What it does not reinvent

Usage collection. Omarchy's own `omarchy-agent-usage-*` collectors write one
JSON record per agent into `~/.local/state/omarchy/agents/usage/`, and this
reads them. A new agent appears the moment a collector writes a record — adding
one never touches this plugin.

## Install

```bash
git clone https://github.com/inocult/omarchy-token-monitor
cd omarchy-token-monitor
./install.sh
```

Which is only: copy `plugin/` to `~/.config/omarchy/plugins/`, `bin/` to
`~/.local/bin/`, `systemd/` to `~/.config/systemd/user/`, then
`omarchy plugin enable <id> right`.

## The three surfaces

| Surface | What it is | Set with |
|---|---|---|
| Bar panel | popup under the bar icon, like network/bluetooth | always on |
| Wing | layer-shell strip pinned to a screen, reserving its own height | `surface wing` (default) |
| Window | an ordinary window, tiled by the compositor | `surface window` |
| — | bar panel only | `dashboard false` |

All three are one process. Quickshell hands you a real xdg-toplevel
(`FloatingWindow`) as readily as a layer surface, so no separate application is
involved — and nothing here declares a `maximumSize`, which is exactly the
mistake that makes a window untileable.

The bar panel's header carries the on/off switch, the way the network and
bluetooth panels hang a control off theirs. Or:

```bash
omarchy bar set inocult.token-monitor surface window   # wing | window
omarchy bar set inocult.token-monitor dashboard false --json
omarchy-shell inocult.token-monitor-wing toggle        # or middle-click the icon
```

The wing sizes itself to its content and reserves exactly that, so the rest of
the workspace tiles normally. `heightPercent 100` gives it the whole screen,
`0` (default) fits the content.

Windowed mode shares one app id with the rest of the shell, so pin it by title:

```lua
o.window({ title = "^Token Monitor$" }, { workspace = "1 silent" })
```

## Settings

`omarchy bar set inocult.token-monitor <key> <value>` (append `--json` for
numbers and booleans, omit it for strings):

| Key | Default | What it does |
|---|---|---|
| `dashboard` | `true` | the header switch writes this |
| `surface` | `wing` | `wing` or `window` |
| `view` | `machine` | which pivot the dashboard opens on |
| `monitor` | *(auto)* | connector for the wing; empty picks the tallest portrait screen |
| `heightPercent` | `0` | `0` fits content, `100` takes the whole screen |
| `showCost` | `true` | show dollars at all |

## Cost

`token-cost` re-scans Claude Code transcripts and writes a priced sidecar to
`~/.local/state/omarchy/agents/usage-cost/`.

It re-scans rather than reading the usage record, and that is not redundancy.
The record's `modelUsage` is **all-time**, and its per-day figures are a single
scalar each — `recentDays[].messageCount` is a token total despite the name.
The four token categories differ in price by up to 50×, and on a real coding
day cache reads are ~98% of the tokens but ~60% of the cost. Sharing out a day's
dollars by its token count is a guess that happens to land within ~2% while the
mix holds, and silently stops being true when it doesn't.

Rates are USD per million, four per model, applied as a dot product — cache
reads and cache writes are their own line items, not a discount on input. A
model with no rate produces **no** cost rather than a wrong one. Refresh from
LiteLLM with `token-cost --update-rates`; inspect with `token-cost --rates`.

## Fleet

`agents-pull` reads each remote's Omarchy records over SSH and shapes them
locally, on a 10-minute systemd user timer.

**Nothing is installed on the remotes.** They already have Omarchy's collectors;
this reads their output. Adding a machine is one row in the `EDIT HERE` block —
not a deployment. It pulls rather than accepts pushes, because the machine that
wants the data is the one that should ask for it, and a remote behind NAT can
still be read over a tailnet.

It writes two files per machine:

- `agents/sync/<device>.json` — the shape `omarchy.agents` merges, so that panel
  benefits too
- `agents/fleet/<device>.json` — the whole record, limits included, which is the
  only way to show every subscription separately

A snapshot that is not from today has its `today*` fields zeroed on the way in.
The merge applies no freshness cutoff of its own, so a machine that has been off
since Tuesday would otherwise keep reporting Tuesday's work as today's.

## Requirements

Omarchy (Quickshell shell), Python 3, and `ssh` if you want the fleet view.

## Licence

MIT.
