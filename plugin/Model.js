// Numbers, rates and merging. No QML types in here on purpose: everything in
// this file is testable by reading it, which is not true of anything that
// touches a FileView.

// ---------------------------------------------------------------- formatting

function compactTokens(value) {
  var n = Number(value) || 0
  if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "B"
  if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
  if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "k"
  return String(Math.round(n))
}

function groupedTokens(value) {
  return String(Math.round(Number(value) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// Under ten dollars the cents matter, over a hundred they are noise on a
// glanceable screen.
function money(value) {
  var n = Number(value) || 0
  if (n >= 100) return "$" + n.toFixed(0)
  if (n >= 10) return "$" + n.toFixed(1)
  return "$" + n.toFixed(2)
}

function moneyExact(value) {
  return "$" + (Number(value) || 0).toFixed(2)
}

function shortDay(dateString) {
  var parts = String(dateString || "").split("-")
  if (parts.length !== 3) return String(dateString || "")
  var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()]
}

function todayDate() {
  var now = new Date()
  return now.getFullYear() + "-"
    + String(now.getMonth() + 1).padStart(2, "0") + "-"
    + String(now.getDate()).padStart(2, "0")
}

// "4m ago". Anything past a day is a staleness problem, not a timestamp.
function ago(isoString, nowMs) {
  var then = Date.parse(String(isoString || ""))
  if (!isFinite(then)) return ""
  var seconds = Math.max(0, ((nowMs || Date.now()) - then) / 1000)
  if (seconds < 90) return "just now"
  if (seconds < 5400) return Math.round(seconds / 60) + "m ago"
  if (seconds < 172800) return Math.round(seconds / 3600) + "h ago"
  return Math.round(seconds / 86400) + "d ago"
}

function untilReset(isoString, nowMs) {
  var then = Date.parse(String(isoString || ""))
  if (!isFinite(then)) return ""
  var seconds = (then - (nowMs || Date.now())) / 1000
  if (seconds <= 0) return "resetting"
  if (seconds < 3600) return Math.max(1, Math.round(seconds / 60)) + "m"
  if (seconds < 172800) return Math.round(seconds / 3600) + "h"
  return Math.round(seconds / 86400) + "d"
}

// --------------------------------------------------------------------- rates
//
// USD per 1,000,000 tokens. Four independent rates per model, because cache
// reads and cache writes are their own line items rather than a discount on
// the input rate -- on Opus 5 a cache read is 1/50th of an output token, and
// cache reads are ~98% of the tokens a coding session moves. Getting this
// wrong does not shade the number, it changes it several times over.
//
// Kept in step with ~/.local/bin/token-cost, which owns the authoritative copy
// and can refresh it from LiteLLM. This table prices what that script cannot:
// the all-time totals and the per-device rows merged in from other machines,
// where all we ever have is a model name and four token counts.
//
// null means the provider does not bill that category at all (OpenAI creates
// cached input for free). That is not the same as "rate unknown" -- an unknown
// rate makes the row report no cost rather than a wrong one.
var RATES_AS_OF = "2026-09-11"
var RATES = {
  "claude-opus-5":       { input: 5.00, output: 25.00, cacheWrite: 6.25, cacheRead: 0.50 },
  "claude-opus-4-5":     { input: 5.00, output: 25.00, cacheWrite: 6.25, cacheRead: 0.50 },
  "claude-sonnet-5":     { input: 2.00, output: 10.00, cacheWrite: 2.50, cacheRead: 0.20 },
  "claude-haiku-4-5":    { input: 1.00, output: 5.00,  cacheWrite: 1.25, cacheRead: 0.10 },
  "claude-fable-5":      { input: 10.00, output: 50.00, cacheWrite: 12.50, cacheRead: 1.00 },
  "claude-fable-5-1":    { input: 10.00, output: 50.00, cacheWrite: 12.50, cacheRead: 0.25 },
  "gpt-5.5":             { input: 5.00, output: 30.00, cacheWrite: null, cacheRead: 0.50 },
  "gpt-5.3-codex":       { input: 1.75, output: 14.00, cacheWrite: null, cacheRead: 0.175 },
  "gpt-5.2-codex":       { input: 1.75, output: 14.00, cacheWrite: null, cacheRead: 0.175 },
  "gpt-5.2":             { input: 1.75, output: 14.00, cacheWrite: null, cacheRead: 0.175 },
  "gpt-5.1-codex-max":   { input: 1.25, output: 10.00, cacheWrite: null, cacheRead: 0.125 },
  "gpt-5.1-codex":       { input: 1.25, output: 10.00, cacheWrite: null, cacheRead: 0.125 },
  "gpt-5.1-codex-mini":  { input: 0.25, output: 2.00,  cacheWrite: null, cacheRead: 0.025 },
  "gpt-5.1":             { input: 1.25, output: 10.00, cacheWrite: null, cacheRead: 0.125 },
  "gpt-5":               { input: 1.25, output: 10.00, cacheWrite: null, cacheRead: 0.125 },
  "gpt-5-codex":         { input: 1.25, output: 10.00, cacheWrite: null, cacheRead: 0.125 },
  "gpt-5-mini":          { input: 0.25, output: 2.00,  cacheWrite: null, cacheRead: 0.025 },
  "gpt-5-nano":          { input: 0.05, output: 0.40,  cacheWrite: null, cacheRead: 0.005 },
  "codex-mini-latest":   { input: 1.50, output: 6.00,  cacheWrite: null, cacheRead: 0.375 }
}

// claude-opus-5[1m] is claude-opus-5 on a longer leash, not a price tier --
// Anthropic publishes no long-context surcharge for it -- so the bracketed
// suffix is dropped rather than left to miss the table.
function normalizeModel(value) {
  var model = String(value || "").trim().toLowerCase()
  var bracket = model.lastIndexOf("[")
  if (bracket > 0 && model.charAt(model.length - 1) === "]") model = model.slice(0, bracket)
  return model.trim()
}

// The record's own field names, which are not ours.
function bucketOf(usage) {
  return {
    input: Number((usage && usage.inputTokens) || 0),
    output: Number((usage && usage.outputTokens) || 0),
    cacheWrite: Number((usage && usage.cacheCreationInputTokens) || 0),
    cacheRead: Number((usage && usage.cacheReadInputTokens) || 0)
  }
}

function bucketTotal(bucket) {
  return bucket.input + bucket.output + bucket.cacheWrite + bucket.cacheRead
}

// Null, not a partial sum, when a category with tokens in it has no rate: an
// under-reported bill that looks precise is worse than an admitted gap.
function costOf(bucket, model) {
  var rates = RATES[normalizeModel(model)]
  if (!rates) return null
  var categories = ["input", "output", "cacheWrite", "cacheRead"]
  var total = 0
  for (var i = 0; i < categories.length; i++) {
    var count = bucket[categories[i]] || 0
    if (!count) continue
    var rate = rates[categories[i]]
    if (rate === null || rate === undefined || !isFinite(rate)) return null
    total += count * rate / 1e6
  }
  return total
}

// { models: [{model, tokens, cost, bucket}], tokens, cost, complete }
function priceModelUsage(modelUsage) {
  var rows = []
  var tokens = 0
  var cost = 0
  var complete = true
  for (var model in (modelUsage || {})) {
    var bucket = bucketOf(modelUsage[model])
    var total = bucketTotal(bucket)
    if (!total) continue
    var rowCost = costOf(bucket, model)
    if (rowCost === null) complete = false
    else cost += rowCost
    tokens += total
    rows.push({ model: normalizeModel(model), tokens: total, cost: rowCost, bucket: bucket })
  }
  rows.sort(function (a, b) { return b.tokens - a.tokens })
  return { models: rows, tokens: tokens, cost: cost, complete: complete }
}

// A remote machine has no cost sidecar of its own -- nothing of ours runs
// there. What its snapshot does carry is today's tokens per model as a single
// number, plus that model's all-time four-way split. Splitting today by that
// model's own long-run mix is an estimate, but a far better one than any flat
// assumption: it is the same model doing the same kind of work, and the ratio
// that matters (cache reads against output) is a property of how the agent is
// used rather than of the day.
//
// Still an estimate, and labelled as one wherever it is shown. The local
// machine's figure is never estimated -- token-cost buckets the real four
// categories per day from the transcripts.
function estimateTodayCost(providers) {
  var total = 0
  var estimated = false

  for (var id in (providers || {})) {
    var stats = providers[id] || {}
    var today = stats.todayTokensByModel || {}
    var allTime = stats.modelUsage || {}

    for (var model in today) {
      var tokens = Number(today[model] || 0)
      if (!tokens) continue

      var mix = bucketOf(allTime[model])
      var mixTotal = bucketTotal(mix)
      if (!mixTotal) continue

      var cost = costOf({
        input: mix.input / mixTotal * tokens,
        output: mix.output / mixTotal * tokens,
        cacheWrite: mix.cacheWrite / mixTotal * tokens,
        cacheRead: mix.cacheRead / mixTotal * tokens
      }, model)

      if (cost !== null) {
        total += cost
        estimated = true
      }
    }
  }
  return { cost: total, estimated: estimated }
}

// ------------------------------------------------------------------ devices
//
// One row per machine. The panel that ships with Omarchy merges the fleet into
// a single set of totals and tells you only how many devices went into it;
// this keeps them apart, because "which machine is burning the budget" is the
// question a desk with four of them actually asks.

function deviceRows(snapshots, localName, localRecords, nowMs) {
  var rows = []
  var today = todayDate()

  function push(device, providers, updatedAt, isLocal) {
    var tokensToday = 0
    var usage = {}
    for (var id in (providers || {})) {
      var stats = providers[id] || {}
      tokensToday += Number(stats.todayTotalTokens || 0)
      var models = stats.modelUsage || {}
      for (var model in models) {
        var key = normalizeModel(model)
        var into = usage[key] || (usage[key] = { inputTokens: 0, outputTokens: 0,
                                                 cacheCreationInputTokens: 0, cacheReadInputTokens: 0 })
        var from = models[model] || {}
        into.inputTokens += Number(from.inputTokens || 0)
        into.outputTokens += Number(from.outputTokens || 0)
        into.cacheCreationInputTokens += Number(from.cacheCreationInputTokens || 0)
        into.cacheReadInputTokens += Number(from.cacheReadInputTokens || 0)
      }
    }
    var priced = priceModelUsage(usage)
    rows.push({
      device: device,
      local: !!isLocal,
      tokensToday: tokensToday,
      tokens: priced.tokens,
      cost: priced.cost,
      complete: priced.complete,
      updatedAt: updatedAt || "",
      // A snapshot that is not from today is still counted in the all-time
      // totals but must not colour today's: the machine may simply be shut.
      stale: !!updatedAt && String(updatedAt).slice(0, 10) !== today && ago(updatedAt, nowMs) !== "just now"
    })
  }

  // This machine comes from the live records rather than from its own
  // snapshot, so the dashboard is never a refresh cycle behind itself.
  var localProviders = {}
  for (var i = 0; i < (localRecords || []).length; i++) {
    var record = localRecords[i]
    if (record && record.id) localProviders[String(record.id)] = record
  }
  push(localName || "this machine", localProviders, new Date().toISOString(), true)

  for (var s = 0; s < (snapshots || []).length; s++) {
    var snapshot = snapshots[s]
    if (!snapshot || !snapshot.providers) continue
    var id = String(snapshot.deviceId || "")
    if (!id || id === localName) continue
    push(id, snapshot.providers, snapshot.updatedAt, false)
  }

  rows.sort(function (a, b) {
    if (a.local !== b.local) return a.local ? -1 : 1
    return b.tokens - a.tokens
  })
  return rows
}

// Seven days, oldest first, summed across every machine. recentDays is keyed
// by date and messageCount is a token total despite the name -- the first-party
// collector says so, and its snapshots keep the old field name so mixed
// versions still merge.
function weekRows(localRecords, snapshots) {
  var window = []
  var now = new Date()
  for (var offset = 6; offset >= 0; offset--) {
    var date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset)
    window.push(date.getFullYear() + "-"
      + String(date.getMonth() + 1).padStart(2, "0") + "-"
      + String(date.getDate()).padStart(2, "0"))
  }

  var totals = {}
  for (var w = 0; w < window.length; w++) totals[window[w]] = 0

  function absorb(days) {
    for (var d = 0; d < (days || []).length; d++) {
      var day = days[d] || {}
      var date = String(day.date || "")
      if (totals[date] !== undefined) totals[date] += Number(day.messageCount || 0)
    }
  }

  for (var i = 0; i < (localRecords || []).length; i++) {
    if (localRecords[i]) absorb(localRecords[i].recentDays)
  }
  for (var s = 0; s < (snapshots || []).length; s++) {
    var providers = (snapshots[s] || {}).providers || {}
    for (var id in providers) absorb((providers[id] || {}).recentDays)
  }

  var rows = []
  var peak = 1
  for (var k = 0; k < window.length; k++) peak = Math.max(peak, totals[window[k]])
  for (var r = 0; r < window.length; r++) {
    rows.push({
      date: window[r],
      label: shortDay(window[r]),
      tokens: totals[window[r]],
      ratio: totals[window[r]] / peak,
      today: window[r] === todayDate()
    })
  }
  return rows
}

// ------------------------------------------------------------ subscriptions
//
// The thing this desk actually wants to see: every plan it pays for, wherever
// it is signed in, side by side.
//
// This CANNOT come from the merged fleet totals, and the reason is worth
// keeping. Omarchy's sync format drops limits and plan on purpose -- a rate
// limit belongs to an account, and two machines signed into two different
// Claude accounts (say Max 20x on one, Max 5x on the other) have two separate
// allowances. Adding or averaging them describes neither. So subscriptions are
// carried per machine, in their own file, and only ever displayed side by side.
//
// Same account on two machines is one subscription, not two. The identity used
// is agent + plan + the exact reset timestamps, because two machines on one
// account are counting down the same window to the same second, and two
// accounts never are.
function subscriptionRows(localRecords, localName, fleet) {
  var byKey = {}
  var order = []

  function absorb(device, records) {
    for (var i = 0; i < (records || []).length; i++) {
      var record = records[i]
      if (!record || !record.id) continue

      var limits = record.limits || []
      var stamps = []
      for (var l = 0; l < limits.length; l++) stamps.push(String((limits[l] || {}).resetsAt || ""))
      var key = String(record.id) + "|" + String(record.tierLabel || "") + "|" + stamps.join(",")

      var row = byKey[key]
      if (!row) {
        row = byKey[key] = {
          agent: String(record.id),
          name: String(record.name || record.id),
          tier: String(record.tierLabel || ""),
          ready: record.ready === true,
          status: String(record.usageStatusText || ""),
          help: String(record.authHelpText || ""),
          devices: [],
          limits: []
        }
        for (var k = 0; k < limits.length; k++) {
          var limit = limits[k] || {}
          var percent = Number(limit.percent || 0)
          row.limits.push({
            label: String(limit.title || limit.label || ""),
            percent: percent,
            resetsAt: String(limit.resetsAt || ""),
            alarming: percent >= 0.9
          })
        }
        order.push(key)
      }
      if (row.devices.indexOf(device) === -1) row.devices.push(device)
      row.ready = row.ready || record.ready === true
    }
  }

  absorb(localName || "this machine", localRecords)
  for (var f = 0; f < (fleet || []).length; f++) {
    var bundle = fleet[f]
    if (bundle && bundle.agents) absorb(String(bundle.deviceId || "remote"), bundle.agents)
  }

  var rows = []
  for (var o = 0; o < order.length; o++) rows.push(byKey[order[o]])

  // A plan with a live allowance first and the most used of those at the top:
  // the one about to run out is the one worth the glance.
  rows.sort(function (a, b) {
    var aHas = a.limits.length > 0
    var bHas = b.limits.length > 0
    if (aHas !== bHas) return aHas ? -1 : 1
    if (aHas) return worstPercent(b) - worstPercent(a)
    return a.name.localeCompare(b.name)
  })
  return rows
}

// ---------------------------------------------------------------- machines
//
// The same facts as subscriptionRows, pivoted. Machine first, then what that
// machine is signed into -- so "what is that box running, and how close is
// each of its plans to the ceiling" is one block rather than a hunt across
// four cards.
//
// Which pivot is the useful one depends on the question, which is why both
// exist and the panel can switch: by machine answers "what is that box doing",
// by subscription answers "how much of what I pay for is left".
function machineGroups(localRecords, localName, fleet, nowMs) {
  var groups = []

  function build(device, isLocal, agents, updatedAt) {
    var usage = {}
    var subscriptions = []

    for (var i = 0; i < (agents || []).length; i++) {
      var record = agents[i]
      if (!record || !record.id) continue

      var models = record.modelUsage || {}
      for (var model in models) {
        var key = normalizeModel(model)
        var into = usage[key] || (usage[key] = { inputTokens: 0, outputTokens: 0,
                                                 cacheCreationInputTokens: 0, cacheReadInputTokens: 0 })
        var from = models[model] || {}
        into.inputTokens += Number(from.inputTokens || 0)
        into.outputTokens += Number(from.outputTokens || 0)
        into.cacheCreationInputTokens += Number(from.cacheCreationInputTokens || 0)
        into.cacheReadInputTokens += Number(from.cacheReadInputTokens || 0)
      }

      var limits = []
      var recordLimits = record.limits || []
      for (var l = 0; l < recordLimits.length; l++) {
        var limit = recordLimits[l] || {}
        var percent = Number(limit.percent || 0)
        limits.push({
          label: String(limit.title || limit.label || ""),
          percent: percent,
          resetsAt: String(limit.resetsAt || ""),
          alarming: percent >= 0.9
        })
      }

      var todayTokens = Number(record.todayTotalTokens || 0)
      subscriptions.push({
        agent: String(record.id),
        name: String(record.name || record.id),
        tier: String(record.tierLabel || ""),
        ready: record.ready === true,
        status: String(record.usageStatusText || ""),
        help: String(record.authHelpText || ""),
        todayTokens: todayTokens,
        limits: limits
      })
    }

    // A plan with a live allowance first, worst first among those: the one
    // about to run out is the one worth the glance.
    subscriptions.sort(function (a, b) {
      var aHas = a.limits.length > 0
      var bHas = b.limits.length > 0
      if (aHas !== bHas) return aHas ? -1 : 1
      if (aHas) return worstPercent(b) - worstPercent(a)
      return b.todayTokens - a.todayTokens
    })

    var priced = priceModelUsage(usage)
    var today = todayDate()
    groups.push({
      device: device,
      local: !!isLocal,
      tokens: priced.tokens,
      cost: priced.cost,
      complete: priced.complete,
      updatedAt: updatedAt || "",
      stale: !!updatedAt && String(updatedAt).slice(0, 10) !== today && ago(updatedAt, nowMs) !== "just now",
      subscriptions: subscriptions
    })
  }

  build(localName || "this machine", true, localRecords, new Date().toISOString())
  for (var f = 0; f < (fleet || []).length; f++) {
    var bundle = fleet[f]
    if (!bundle || !bundle.agents) continue
    var id = String(bundle.deviceId || "")
    if (!id || id === localName) continue
    build(id, false, bundle.agents, bundle.updatedAt)
  }

  groups.sort(function (a, b) {
    if (a.local !== b.local) return a.local ? -1 : 1
    return b.tokens - a.tokens
  })
  return groups
}

// "Session (5-hour)" -> "Session". The window length is already on the row as
// a live countdown, so spelling it out again costs the width the label needs.
function shortLimit(label) {
  return String(label || "").replace(/\s*\([^)]*\)\s*/g, " ").trim()
}

function worstPercent(row) {
  var worst = 0
  for (var i = 0; i < (row.limits || []).length; i++) worst = Math.max(worst, row.limits[i].percent)
  return worst
}

// Limits never travel between machines -- they are per account, and merging
// two accounts' percentages would produce a number that is true of neither.
// Always the local record's.
function limitRows(records) {
  var rows = []
  for (var i = 0; i < (records || []).length; i++) {
    var record = records[i]
    var limits = (record && record.limits) || []
    for (var l = 0; l < limits.length; l++) {
      var limit = limits[l] || {}
      var percent = Number(limit.percent || 0)
      rows.push({
        agent: String(record.name || record.id || ""),
        label: String(limit.title || limit.label || ""),
        percent: percent,
        resetsAt: String(limit.resetsAt || ""),
        alarming: percent >= 0.9
      })
    }
  }
  return rows
}
