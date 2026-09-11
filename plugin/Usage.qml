import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Everything the dashboard knows, and nothing it draws.
//
// Three sources, all files, all watched:
//
//   ~/.local/state/omarchy/agents/usage/*.json       first-party records: tokens
//                                                    and rate limits, this machine
//   ~/.local/state/omarchy/agents/usage-cost/*.json  ~/.local/bin/token-cost: the
//                                                    per-day four-way token split
//                                                    priced in dollars
//   ~/.local/state/omarchy/agents/sync/*.json        one snapshot per other machine,
//                                                    fetched by ~/.local/bin/agents-pull
//
// Nothing here talks to the network or to a remote. Collection belongs to the
// collectors and the pull belongs to the timer; a status surface that blocks on
// an SSH round trip is a status surface that hangs.
Item {
  id: root
  visible: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents"
  readonly property string usageDir: stateDir + "/usage"
  readonly property string costDir: stateDir + "/usage-cost"
  readonly property string syncDir: stateDir + "/sync"
  readonly property string fleetDir: stateDir + "/fleet"

  property var records: []
  property var costRecords: ({})
  property var snapshots: []
  property var fleet: []
  property int revision: 0
  property string hostname: ""

  // Countdowns and "updated 4m ago" read this rather than Date.now(), so the
  // dashboard keeps telling the truth while it sits open for hours.
  property double nowMs: Date.now()

  // ------------------------------------------------------------- derived

  readonly property var limits: revision, Model.limitRows(records)
  readonly property var week: revision, Model.weekRows(records, snapshots)
  readonly property var devices: revision, Model.deviceRows(snapshots, hostname, records, nowMs)
  readonly property var subscriptions: revision, Model.subscriptionRows(records, hostname, fleet)
  readonly property var machines: revision, Model.machineGroups(records, hostname, fleet, nowMs)

  // Named totals, not fleet: `fleet` is the per-machine bundles above.
  readonly property var totals: {
    revision
    var usage = {}
    function absorb(modelUsage) {
      for (var model in (modelUsage || {})) {
        var key = Model.normalizeModel(model)
        var into = usage[key] || (usage[key] = { inputTokens: 0, outputTokens: 0,
                                                 cacheCreationInputTokens: 0, cacheReadInputTokens: 0 })
        var from = modelUsage[model] || {}
        into.inputTokens += Number(from.inputTokens || 0)
        into.outputTokens += Number(from.outputTokens || 0)
        into.cacheCreationInputTokens += Number(from.cacheCreationInputTokens || 0)
        into.cacheReadInputTokens += Number(from.cacheReadInputTokens || 0)
      }
    }
    for (var i = 0; i < records.length; i++) if (records[i]) absorb(records[i].modelUsage)
    for (var s = 0; s < snapshots.length; s++) {
      var providers = (snapshots[s] || {}).providers || {}
      for (var id in providers) absorb((providers[id] || {}).modelUsage)
    }
    return Model.priceModelUsage(usage)
  }

  readonly property var models: totals.models
  readonly property real allTimeTokens: totals.tokens
  readonly property real allTimeCost: totals.cost
  readonly property bool allTimeComplete: totals.complete

  // Today's tokens come from the records because they are what every machine
  // agrees on. Today's COST comes from the sidecar, because the records carry
  // no per-day split and the four token categories differ in price by 50x --
  // sharing out a day's dollars by its token count is a guess that happens to
  // be close while the day's mix holds and silently is not when it does not.
  readonly property real todayTokens: {
    revision
    var total = 0
    for (var i = 0; i < records.length; i++) total += Number((records[i] || {}).todayTotalTokens || 0)
    for (var s = 0; s < snapshots.length; s++) {
      var providers = (snapshots[s] || {}).providers || {}
      for (var id in providers) total += Number((providers[id] || {}).todayTotalTokens || 0)
    }
    return total
  }

  readonly property real todayCost: {
    revision
    var total = 0
    for (var agent in costRecords) {
      var today = (costRecords[agent] || {}).today
      if (today) total += Number(today.costUsd || 0)
    }
    return total
  }

  // Remote machines have no cost sidecar of their own, so their share is
  // priced here from the model split in their snapshot. Said plainly in the
  // UI rather than folded in silently, because it is a different method.
  readonly property bool todayCostLocalOnly: snapshots.length > 0

  readonly property bool priced: {
    revision
    for (var agent in costRecords) return true
    return false
  }

  readonly property string ratesAsOf: {
    revision
    for (var agent in costRecords) {
      var stamp = (costRecords[agent] || {}).ratesAsOf
      if (stamp) return String(stamp)
    }
    return Model.RATES_AS_OF
  }

  readonly property string updatedAt: {
    revision
    var newest = ""
    for (var i = 0; i < records.length; i++) {
      var stamp = String((records[i] || {}).updatedAt || "")
      if (stamp > newest) newest = stamp
    }
    return newest
  }

  signal changed()

  function bump() {
    revision++
    changed()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // ------------------------------------------------------------ discovery
  //
  // One find per directory rather than a FileView per guessed name: an agent
  // this build has never heard of should appear on its own the first time a
  // collector writes a record, which is the whole point of the record contract.

  property var usageIds: []
  property var costIds: []

  function scanDir(dir, apply) {
    var script = "dir=$0; [[ -d \"$dir\" ]] || exit 0; shopt -s nullglob; "
      + "for f in \"$dir\"/*.json; do [[ -f \"$f\" ]] || continue; printf '%s\\n' \"$(basename \"$f\" .json)\"; done"
    return ["bash", "-c", script, dir]
  }

  function applyIds(text, current) {
    var ids = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var name = lines[i].trim()
      if (name !== "") ids.push(name)
    }
    ids.sort()
    // Same list, same objects: reassigning would tear down every FileView to
    // rebuild identical ones, and each rebuild is a file read.
    return JSON.stringify(ids) === JSON.stringify(current) ? current : ids
  }

  Process {
    id: usageScan
    command: root.scanDir(root.usageDir)
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.usageIds = root.applyIds(text, root.usageIds) }
  }

  Process {
    id: costScan
    command: root.scanDir(root.costDir)
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.costIds = root.applyIds(text, root.costIds) }
  }

  function rescan() {
    if (!usageScan.running) usageScan.running = true
    if (!costScan.running) costScan.running = true
    if (!syncScan.running) syncScan.running = true
    if (!fleetScan.running) fleetScan.running = true
  }

  Instantiator {
    id: usageFiles
    model: root.usageIds
    delegate: JsonFile {
      required property var modelData
      path: root.usageDir + "/" + modelData + ".json"
      onParsed: root.rebuildRecords()
    }
    onObjectAdded: root.rebuildRecords()
    onObjectRemoved: root.rebuildRecords()
  }

  Instantiator {
    id: costFiles
    model: root.costIds
    delegate: JsonFile {
      required property var modelData
      path: root.costDir + "/" + modelData + ".json"
      onParsed: root.rebuildCosts()
    }
    onObjectAdded: root.rebuildCosts()
    onObjectRemoved: root.rebuildCosts()
  }

  function rebuildRecords() {
    var result = []
    for (var i = 0; i < usageFiles.count; i++) {
      var file = usageFiles.objectAt(i)
      if (file && file.value) result.push(file.value)
    }
    records = result
    bump()
    costDebounce.restart()
  }

  function rebuildCosts() {
    var result = {}
    for (var i = 0; i < costFiles.count; i++) {
      var file = costFiles.objectAt(i)
      if (file && file.value && file.value.agent) result[String(file.value.agent)] = file.value
    }
    costRecords = result
    bump()
  }

  // ----------------------------------------------------------------- sync
  //
  // Read in one pass with a framing marker rather than a FileView each: the
  // set of machines changes when a script drops a file in, not on a schedule,
  // and a torn read here would show a device as missing rather than as stale.

  Process {
    id: syncScan
    command: ["bash", "-c",
      "dir=$0; [[ -d \"$dir\" ]] || exit 0; shopt -s nullglob; "
      + "for f in \"$dir\"/*.json; do [[ -f \"$f\" ]] || continue; "
      + "printf '===%s===\\n' \"$f\"; cat \"$f\"; printf '\\n=== EOM ===\\n'; done",
      root.syncDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = []
        var chunks = String(text || "").split("=== EOM ===")
        for (var i = 0; i < chunks.length; i++) {
          var body = chunks[i]
          var marker = body.indexOf("===")
          if (marker === -1) continue
          var end = body.indexOf("===", marker + 3)
          if (end === -1) continue
          var json = body.slice(end + 3).trim()
          if (json === "") continue
          try {
            var parsed = JSON.parse(json)
            if (parsed && parsed.providers) found.push(parsed)
          } catch (error) {
            console.warn("token-monitor", "ignoring unreadable snapshot", error)
          }
        }
        root.snapshots = found
        root.bump()
      }
    }
  }

  Process {
    id: fleetScan
    command: ["bash", "-c",
      "dir=$0; [[ -d \"$dir\" ]] || exit 0; shopt -s nullglob; "
      + "for f in \"$dir\"/*.json; do [[ -f \"$f\" ]] || continue; "
      + "printf '===%s===\\n' \"$f\"; cat \"$f\"; printf '\\n=== EOM ===\\n'; done",
      root.fleetDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = []
        var chunks = String(text || "").split("=== EOM ===")
        for (var i = 0; i < chunks.length; i++) {
          var body = chunks[i]
          var marker = body.indexOf("===")
          if (marker === -1) continue
          var end = body.indexOf("===", marker + 3)
          if (end === -1) continue
          var json = body.slice(end + 3).trim()
          if (json === "") continue
          try {
            var parsed = JSON.parse(json)
            if (parsed && parsed.agents) found.push(parsed)
          } catch (error) {
            console.warn("token-monitor", "ignoring unreadable fleet bundle", error)
          }
        }
        root.fleet = found
        root.bump()
      }
    }
  }

  // ---------------------------------------------------------------- costing
  //
  // token-cost is local, reads only files, and takes about a tenth of a second,
  // so it runs whenever the tokens move rather than on a clock -- the dashboard
  // never shows fresh tokens beside an hour-old price. Debounced because
  // omarchy-agent-usage-update rewrites every record at once and one run
  // covers all of them.

  Timer {
    id: costDebounce
    interval: 1200
    onTriggered: if (!costProcess.running) costProcess.running = true
  }

  Process {
    id: costProcess
    running: false
    command: ["bash", "-lc", "token-cost >/dev/null"]
    onExited: root.rescan()
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") console.warn("token-monitor", text.trim())
    }
  }

  FileView {
    path: "/etc/hostname"
    watchChanges: false
    printErrors: false
    onLoaded: root.hostname = String(text() || "").trim()
  }

  // A directory watch would be better than a poll, but the set of files changes
  // only when a collector or the pull timer writes one, and both are minutes
  // apart. Cheap poll, no inotify process to supervise.
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.rescan()
  }

  component JsonFile: Item {
    id: file
    property string path: ""
    property var value: null
    signal parsed()

    FileView {
      path: file.path
      watchChanges: true
      printErrors: false
      // text() is stale inside the change signal, so both paths go through
      // reload() and come back as onLoaded with fresh content.
      onFileChanged: reload()
      onLoaded: {
        try {
          var parsed = JSON.parse(String(text() || ""))
          file.value = parsed && typeof parsed === "object" ? parsed : null
        } catch (error) {
          console.warn("token-monitor", "ignoring bad record", file.path, error)
          file.value = null
        }
        file.parsed()
      }
      onLoadFailed: {
        file.value = null
        file.parsed()
      }
    }
  }
}
