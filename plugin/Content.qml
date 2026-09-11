import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The dashboard itself, with no opinion about what it is mounted in.
//
// Used twice: as the body of the bar popup, and as the body of the wing or
// window. Separately-written layouts would drift apart the first time either
// was touched, and the point of both is to look like the rest of the bar.
//
// SYNTHESIS, NOT SCROLLING. Every section states its conclusion on its own
// header line and opens for the working. An earlier version laid all of it out
// at once, and for a panel you open to answer "how close am I to the ceiling"
// that is the wrong shape -- you had to scroll past the answer to find it.
// Visible without touching anything: today's spend, and one bar per machine
// against its tightest limit.
Column {
  id: root

  property var usage: null
  property bool showCost: true

  // Compact is the bar popup; the wing and window have room and open trends.
  property bool compact: false

  // The bar popup passes its on/off switch, the way the network and bluetooth
  // panels hang a control off their hero.
  property Component trailingControl: null

  // function(key, value) -- how this surface persists a setting, and the
  // settings it currently has. Supplied by the mount, because a bar widget and
  // a panel plugin reach the shell by different routes.
  property var settingsWriter: null
  property var settingsSource: ({})
  function put(key, value) { if (settingsWriter) settingsWriter(key, value) }
  function held(key, fallback) {
    var value = settingsSource ? settingsSource[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  property string view: "machine"
  function toggleView() { view = view === "machine" ? "subscription" : "machine" }

  // Which machines are opened. A plain object rather than state on the rows, so
  // it survives the model being rebuilt on every refresh.
  property var opened: ({})
  function isOpen(key) { return opened[key] === true }
  function toggleOpen(key) {
    var next = {}
    for (var k in opened) next[k] = opened[k]
    next[key] = !next[key]
    opened = next
  }

  property bool trendsOpen: !compact
  property bool modelsOpen: false
  property bool settingsOpen: false

  spacing: Style.space(12)

  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color fainter: Qt.darker(fg, 1.9)
  readonly property color track: Style.selectedFillFor(fg, Color.accent)
  readonly property string face: Style.fontFamily

  // The line under the title, and the part of the header that moves. It cycles
  // rather than concatenating: the hero elides that line and the trailing
  // switch takes the width a full sentence needs, so a joined string rendered
  // as three facts truncated into none.
  property int tick: 0

  Timer {
    interval: 4000
    running: root.visible
    repeat: true
    onTriggered: root.tick++
  }

  readonly property var facts: {
    if (!usage) return ["waiting for a collector"]
    if (usage.updatedAt === "") return ["no collector has run yet"]

    var out = []
    var machines = usage.devices.length
    var subs = usage.subscriptions.length
    out.push(machines + (machines === 1 ? " machine" : " machines")
      + " · " + subs + (subs === 1 ? " plan" : " plans"))

    var worst = null
    for (var i = 0; i < usage.limits.length; i++) {
      if (!worst || usage.limits[i].percent > worst.percent) worst = usage.limits[i]
    }
    if (worst && worst.percent > 0) {
      out.push(Model.shortLimit(worst.label).toLowerCase() + " " + Math.round(worst.percent * 100) + "% used")
    }
    if (usage.weekStats.hasTrend) out.push("week " + Model.signedPercent(usage.weekStats.trend))
    out.push("updated " + Model.ago(usage.updatedAt, usage.nowMs))
    return out
  }

  readonly property string status: {
    if (usage && usage.busy) return "pricing transcripts"
    var list = facts
    return list[tick % list.length]
  }

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function markFor(agent) {
    var known = ["claude", "codex", "fireworks"]
    return known.indexOf(String(agent)) === -1 ? "" : Qt.resolvedUrl("assets/" + agent + ".svg")
  }

  // The one number a machine is judged by at a glance: whichever of its
  // allowances is furthest along.
  function tightest(subscriptions) {
    var worst = null
    for (var i = 0; i < (subscriptions || []).length; i++) {
      var limits = subscriptions[i].limits || []
      for (var l = 0; l < limits.length; l++) {
        if (!worst || limits[l].percent > worst.percent) {
          worst = { label: limits[l].label, percent: limits[l].percent,
                    resetsAt: limits[l].resetsAt, alarming: limits[l].alarming }
        }
      }
    }
    return worst
  }

  // ----------------------------------------------------------------- header

  PanelHero {
    width: parent.width
    title: "Token Monitor"
    foreground: root.fg
    fontFamily: root.face
    meta: root.status
    trailingControl: root.trailingControl

    iconComponent: Component {
      Text {
        text: "󱈣"
        color: root.fg
        font.family: root.face
        font.pixelSize: Style.font.display
      }
    }
  }

  // ------------------------------------------------------------------ today

  Column {
    width: parent.width
    spacing: Style.space(2)

    Item {
      width: parent.width
      height: Math.max(priceRow.implicitHeight, tokenRow.implicitHeight)

      Row {
        id: priceRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)
        visible: root.showCost

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(1)
          text: !root.usage || !root.usage.priced ? "--"
            : Model.moneyExact(root.usage.hub ? root.usage.todayCostTotal : root.usage.todayCost)
          color: root.fg
          font.family: root.face
          font.pixelSize: Style.font.display
          font.bold: true
        }

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(4)
          text: "today"
          color: root.fainter
          font.family: root.face
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: tokenRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(1)
          text: Model.compactTokens(root.usage ? root.usage.todayTokens : 0)
          color: root.fg
          font.family: root.face
          font.pixelSize: Style.font.display
          font.bold: true
        }

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(4)
          text: "tokens"
          color: root.fainter
          font.family: root.face
          font.pixelSize: Style.font.caption
        }
      }
    }

    // With one machine there is nothing to say -- these are obviously this
    // machine's -- so the line disappears rather than stating it every time.
    Text {
      visible: root.usage && root.usage.hub
      width: parent.width
      text: {
        if (!root.usage) return ""
        var scope = "all " + root.usage.devices.length + " machines"
        return root.showCost && root.usage.todayCostEstimated
          ? scope + " · other machines' cost estimated" : scope
      }
      color: root.fainter
      elide: Text.ElideRight
      font.family: root.face
      font.pixelSize: Style.font.caption
    }
  }

  // --------------------------------------------------------------- machines

  PanelSeparator { foreground: root.fg; visible: machineList.visible }

  Column {
    id: machineList
    width: parent.width
    spacing: Style.space(7)
    visible: root.view === "machine" && root.usage && root.usage.machines.length > 0

    SectionHead {
      label: "MACHINES"
      hint: root.usage && root.usage.hub ? root.usage.devices.length + " reporting" : ""
      action: "by plan"
      onActivated: root.toggleView()
    }

    Repeater {
      model: root.usage ? root.usage.machines : []
      delegate: Column {
        id: box
        required property var modelData
        readonly property var worst: root.tightest(box.modelData.subscriptions)
        readonly property bool open: root.isOpen(box.modelData.device)
        width: machineList.width
        spacing: Style.space(5)

        Item {
          width: parent.width
          height: boxName.implicitHeight

          Text {
            id: boxName
            anchors.left: parent.left
            text: (box.open ? "▾  " : "▸  ") + box.modelData.device
              + (box.modelData.local ? "  ·  this one" : "")
            color: box.modelData.stale ? root.dim : root.fg
            font.family: root.face
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.baseline: boxName.baseline
            text: Model.compactTokens(box.modelData.tokens)
              + (root.showCost && box.modelData.cost !== null ? "   " + Model.moneyExact(box.modelData.cost) : "")
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleOpen(box.modelData.device)
          }
        }

        // Closed: the one allowance that matters. Open: all of them, per plan.
        LimitBar {
          visible: !box.open && !!box.worst
          width: parent.width
          label: box.worst ? Model.shortLimit(box.worst.label) : ""
          percent: box.worst ? box.worst.percent : 0
          resetsAt: box.worst ? box.worst.resetsAt : ""
          alarming: box.worst ? box.worst.alarming : false
        }

        Text {
          visible: !box.open && !box.worst
          width: parent.width
          text: "no allowance reported"
          color: root.fainter
          font.family: root.face
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: box.open ? box.modelData.subscriptions : []
          delegate: Column {
            id: sub
            required property var modelData
            width: box.width
            spacing: Style.space(3)

            Item {
              width: parent.width
              height: Math.max(subMark.height, subName.implicitHeight)

              Image {
                id: subMark
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                source: root.markFor(sub.modelData.agent)
                visible: source !== ""
                width: Style.space(11); height: width
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                smooth: true
              }

              Text {
                id: subName
                anchors.left: subMark.visible ? subMark.right : parent.left
                anchors.leftMargin: subMark.visible ? Style.space(6) : Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: sub.modelData.name + (sub.modelData.tier !== "" ? "  " + sub.modelData.tier : "")
                color: root.fg
                elide: Text.ElideRight
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: sub.modelData.limits.length === 0
                text: sub.modelData.status !== "" ? sub.modelData.status
                  : (sub.modelData.help !== "" ? "not signed in" : "no limit data")
                color: root.fainter
                font.family: root.face
                font.pixelSize: Style.font.caption
              }
            }

            Repeater {
              model: sub.modelData.limits
              delegate: LimitBar {
                required property var modelData
                width: sub.width
                inset: Style.space(8)
                label: Model.shortLimit(modelData.label)
                percent: modelData.percent
                resetsAt: modelData.resetsAt
                alarming: modelData.alarming
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------- subscriptions

  PanelSeparator { foreground: root.fg; visible: planList.visible }

  Column {
    id: planList
    width: parent.width
    spacing: Style.space(7)
    visible: root.view === "subscription" && root.usage && root.usage.subscriptions.length > 0

    SectionHead {
      label: "SUBSCRIPTIONS"
      action: "by machine"
      onActivated: root.toggleView()
    }

    Repeater {
      model: root.usage ? root.usage.subscriptions : []
      delegate: Column {
        id: plan
        required property var modelData
        width: planList.width
        spacing: Style.space(4)

        Item {
          width: parent.width
          height: Math.max(planMark.height, planName.implicitHeight)

          Image {
            id: planMark
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            source: root.markFor(plan.modelData.agent)
            visible: source !== ""
            width: Style.space(13); height: width
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            smooth: true
          }

          Text {
            id: planName
            anchors.left: planMark.visible ? planMark.right : parent.left
            anchors.leftMargin: planMark.visible ? Style.space(7) : 0
            anchors.verticalCenter: parent.verticalCenter
            text: plan.modelData.name + (plan.modelData.tier !== "" ? "  " + plan.modelData.tier : "")
            color: root.fg
            elide: Text.ElideRight
            font.family: root.face
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: plan.modelData.devices.join(" · ")
            color: root.fainter
            font.family: root.face
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: plan.modelData.limits.length === 0
          width: parent.width
          text: plan.modelData.status !== "" ? plan.modelData.status
            : (plan.modelData.help !== "" ? plan.modelData.help : "no limit data")
          color: root.fainter
          elide: Text.ElideRight
          font.family: root.face
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: plan.modelData.limits
          delegate: LimitBar {
            required property var modelData
            width: plan.width
            label: Model.shortLimit(modelData.label)
            percent: modelData.percent
            resetsAt: modelData.resetsAt
            alarming: modelData.alarming
          }
        }
      }
    }
  }

  // ----------------------------------------------------------------- trends

  PanelSeparator { foreground: root.fg }

  Column {
    width: parent.width
    spacing: Style.space(8)

    SectionHead {
      label: "TRENDS"
      hint: root.usage && root.usage.weekStats.hasTrend
        ? "week " + Model.signedPercent(root.usage.weekStats.trend) : ""
      action: root.trendsOpen ? "hide" : "show"
      onActivated: root.trendsOpen = !root.trendsOpen
    }

    TrendPlot {
      visible: root.trendsOpen
      width: parent.width
      days: root.usage ? root.usage.week : []
      implicitHeight: root.compact ? Style.space(76) : Style.space(108)
    }

    // Four numbers rather than seven bars: the curve says the shape, these say
    // what it amounts to.
    Grid {
      visible: root.trendsOpen
      width: parent.width
      columns: 2
      columnSpacing: Style.space(10)
      rowSpacing: Style.space(5)

      Stat {
        width: (parent.width - Style.space(10)) / 2
        label: "7-day total"
        value: Model.compactTokens(root.usage ? root.usage.weekStats.total : 0)
      }
      Stat {
        width: (parent.width - Style.space(10)) / 2
        label: "busiest day"
        value: root.usage && root.usage.weekStats.peak > 0
          ? root.usage.weekStats.peakLabel + "  " + Model.compactTokens(root.usage.weekStats.peak) : "--"
      }
      Stat {
        width: (parent.width - Style.space(10)) / 2
        label: "per active day"
        value: Model.compactTokens(root.usage ? root.usage.weekStats.average : 0)
      }
      Stat {
        width: (parent.width - Style.space(10)) / 2
        label: "days worked"
        value: root.usage ? root.usage.weekStats.activeDays + " of 7" : "--"
      }
    }
  }

  // --------------------------------------------------------------- by model

  PanelSeparator { foreground: root.fg; visible: modelBlock.visible }

  Column {
    id: modelBlock
    width: parent.width
    spacing: Style.space(4)
    visible: root.usage && root.usage.models.length > 0

    SectionHead {
      label: "BY MODEL"
      hint: root.usage && root.usage.models.length > 0
        ? root.usage.models.length + (root.usage.models.length === 1 ? " model" : " models") : ""
      action: root.modelsOpen ? "hide" : "show"
      onActivated: root.modelsOpen = !root.modelsOpen
    }

    Repeater {
      model: root.modelsOpen && root.usage ? root.usage.models : []
      delegate: BackedRow {
        required property var modelData
        width: modelBlock.width
        share: modelData.tokens / Math.max(1, root.usage.models[0].tokens)
        label: modelData.model
        value: Model.compactTokens(modelData.tokens)
          + (root.showCost && modelData.cost !== null ? "   " + Model.moneyExact(modelData.cost) : "")
      }
    }
  }

  // --------------------------------------------------------------- settings
  //
  // Here, because there is nowhere else. Omarchy keeps a widget's settings in
  // shell.json and a manifest may declare a schema for them, but nothing in the
  // shipped shell renders that schema into a form -- so a plugin that wants a
  // settings surface draws its own.

  PanelSeparator { foreground: root.fg }

  Column {
    width: parent.width
    spacing: Style.space(6)

    SectionHead {
      label: "SETTINGS"
      action: root.settingsOpen ? "hide" : "show"
      onActivated: root.settingsOpen = !root.settingsOpen
    }

    Column {
      visible: root.settingsOpen
      width: parent.width
      spacing: Style.space(6)

      Choice {
        width: parent.width
        label: "Dashboard"
        options: ["wing", "window", "off"]
        current: root.held("dashboard", true) === false ? "off" : String(root.held("surface", "wing"))
        onPicked: function (value) {
          if (value === "off") root.put("dashboard", false)
          else { root.put("surface", value); root.put("dashboard", true) }
        }
      }

      Choice {
        width: parent.width
        label: "Opens on"
        options: ["machine", "subscription"]
        current: root.view
        onPicked: function (value) { root.view = value; root.put("view", value) }
      }

      Choice {
        width: parent.width
        label: "Cost"
        options: ["show", "hide"]
        current: root.showCost ? "show" : "hide"
        onPicked: function (value) { root.put("showCost", value === "show") }
      }

      Item {
        width: parent.width
        height: rates.implicitHeight

        Text {
          id: rates
          anchors.left: parent.left
          text: "rates as of " + (root.usage ? root.usage.ratesAsOf : "")
          color: root.fainter
          font.family: root.face
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.right: parent.right
          anchors.baseline: rates.baseline
          text: "refresh now"
          color: root.dim
          font.family: root.face
          font.pixelSize: Style.font.caption
          font.bold: true

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.usage) root.usage.rescan()
          }
        }
      }
    }
  }

  // ----------------------------------------------------------------- totals

  PanelSeparator { foreground: root.fg }

  Item {
    width: parent.width
    height: allTime.implicitHeight

    Text {
      id: allTime
      text: Model.compactTokens(root.usage ? root.usage.allTimeTokens : 0) + " all time"
      color: root.dim
      font.family: root.face
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.right: parent.right
      visible: root.showCost
      text: Model.moneyExact(root.usage ? root.usage.allTimeCost : 0)
      color: root.dim
      font.family: root.face
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  // ------------------------------------------------------------- components

  // A section title that states its own conclusion and carries the control for
  // opening it. The hint is what you would otherwise have had to expand to see.
  component SectionHead: Item {
    id: head
    property string label: ""
    property string hint: ""
    property string action: ""
    signal activated()

    width: parent ? parent.width : 0
    height: headLabel.implicitHeight

    PanelSectionHeader {
      id: headLabel
      text: head.label
      foreground: root.fg
    }

    Text {
      anchors.left: headLabel.right
      anchors.leftMargin: Style.space(8)
      anchors.right: headAction.left
      anchors.rightMargin: Style.space(8)
      anchors.baseline: headLabel.baseline
      text: head.hint
      color: root.fainter
      elide: Text.ElideRight
      font.family: root.face
      font.pixelSize: Style.font.caption
    }

    Text {
      id: headAction
      anchors.right: parent.right
      anchors.baseline: headLabel.baseline
      visible: head.action !== ""
      text: head.action
      color: root.dim
      font.family: root.face
      font.pixelSize: Style.font.caption

      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(5)
        cursorShape: Qt.PointingHandCursor
        onClicked: head.activated()
      }
    }
  }

  // Label, bar, percentage and countdown on one line. Stacked, these cost three
  // rows per allowance, and a machine with three plans then needs a screen.
  component LimitBar: Item {
    id: bar
    property string label: ""
    property real percent: 0
    property string resetsAt: ""
    property bool alarming: false
    property real inset: 0

    height: Style.space(15)

    Text {
      id: barLabel
      anchors.left: parent.left
      anchors.leftMargin: bar.inset
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(78)
      text: bar.label
      color: root.fainter
      elide: Text.ElideRight
      font.family: root.face
      font.pixelSize: Style.font.caption
    }

    Text {
      id: barValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(54)
      horizontalAlignment: Text.AlignRight
      text: Math.round(bar.percent * 100) + "%"
        + (bar.resetsAt !== "" ? "  " + Model.untilReset(bar.resetsAt, root.usage ? root.usage.nowMs : 0) : "")
      color: bar.alarming ? Color.urgent : root.dim
      font.family: root.face
      font.pixelSize: Style.font.caption
      font.bold: bar.alarming
    }

    Rectangle {
      anchors.left: barLabel.right
      anchors.right: barValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(3), Math.round(Style.spacing.controlHeight * 0.12))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * Math.max(0, Math.min(1, bar.percent))
        color: bar.alarming ? Color.urgent : root.fg
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }
    }
  }

  // Seven days as a curve rather than seven bars. Bars compare magnitudes; the
  // question a week actually asks is which way it is going.
  component TrendPlot: Item {
    id: plot
    property var days: []

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true

      readonly property real peak: {
        var max = 0
        for (var i = 0; i < plot.days.length; i++) max = Math.max(max, Number(plot.days[i].tokens || 0))
        return max
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        var rows = plot.days || []
        if (rows.length < 2) return

        // Inset horizontally by the marker radius: the curve runs to the very
        // edge otherwise and today's dot is drawn half outside the canvas.
        var dot = Style.space(4)
        var padTop = Style.space(8)
        var padBottom = Style.space(16)
        var left = dot + 1
        var w = width - 2 * (dot + 1)
        var h = height - padTop - padBottom
        var top = padTop
        var scale = canvas.peak > 0 ? canvas.peak : 1

        var xs = []
        var ys = []
        for (var i = 0; i < rows.length; i++) {
          xs.push(left + w * i / (rows.length - 1))
          ys.push(top + h - (Number(rows[i].tokens || 0) / scale) * h)
        }

        // Baseline, so an empty stretch reads as zero rather than as missing.
        ctx.strokeStyle = root.alpha(root.fg, 0.12)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(left, top + h + 0.5)
        ctx.lineTo(left + w, top + h + 0.5)
        ctx.stroke()

        // Midpoint quadratics: no control points to tune, and they cannot
        // overshoot below zero the way a cardinal spline can.
        function trace() {
          ctx.moveTo(xs[0], ys[0])
          for (var i = 1; i < xs.length; i++) {
            var mx = (xs[i - 1] + xs[i]) / 2
            var my = (ys[i - 1] + ys[i]) / 2
            ctx.quadraticCurveTo(xs[i - 1], ys[i - 1], mx, my)
          }
          ctx.lineTo(xs[xs.length - 1], ys[ys.length - 1])
        }

        var fill = ctx.createLinearGradient(0, top, 0, top + h)
        fill.addColorStop(0, root.alpha(root.fg, 0.22))
        fill.addColorStop(1, root.alpha(root.fg, 0.0))
        ctx.fillStyle = fill
        ctx.beginPath()
        trace()
        ctx.lineTo(xs[xs.length - 1], top + h)
        ctx.lineTo(xs[0], top + h)
        ctx.closePath()
        ctx.fill()

        ctx.strokeStyle = root.fg
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.beginPath()
        trace()
        ctx.stroke()

        // Today gets a dot; the rest of the week is the line's business.
        var last = xs.length - 1
        ctx.fillStyle = Color.popups.background
        ctx.beginPath()
        ctx.arc(xs[last], ys[last], dot, 0, Math.PI * 2)
        ctx.fill()
        ctx.strokeStyle = root.fg
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.arc(xs[last], ys[last], dot, 0, Math.PI * 2)
        ctx.stroke()

        ctx.fillStyle = root.alpha(root.fg, 0.55)
        ctx.font = Math.round(Style.font.caption) + "px " + root.face
        for (var d = 0; d < rows.length; d++) {
          var label = String(rows[d].label || "")
          var tw = ctx.measureText(label).width
          var tx = Math.max(0, Math.min(width - tw, xs[d] - tw / 2))
          ctx.fillText(label, tx, top + h + Style.space(12))
        }
      }

      Connections {
        target: plot
        function onDaysChanged() { canvas.requestPaint() }
      }
    }

    // The peak, so the curve has a scale without an axis cluttering it.
    Text {
      anchors.right: parent.right
      anchors.top: parent.top
      text: canvas.peak > 0 ? Model.compactTokens(canvas.peak) : ""
      color: root.fainter
      font.family: root.face
      font.pixelSize: Style.font.caption
    }
  }

  component Stat: Column {
    id: stat
    property string label: ""
    property string value: ""
    spacing: 0

    Text {
      text: stat.label
      color: root.fainter
      font.family: root.face
      font.pixelSize: Style.font.caption
    }

    Text {
      width: stat.width
      text: stat.value
      color: root.fg
      elide: Text.ElideRight
      font.family: root.face
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  component Choice: Item {
    id: choice
    property string label: ""
    property var options: []
    property string current: ""
    signal picked(string value)

    height: Math.max(choiceLabel.implicitHeight, chips.implicitHeight)

    Text {
      id: choiceLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: choice.label
      color: root.dim
      font.family: root.face
      font.pixelSize: Style.font.caption
    }

    Row {
      id: chips
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Repeater {
        model: choice.options
        delegate: Rectangle {
          id: chip
          required property var modelData
          readonly property bool active: String(choice.current) === String(modelData)
          width: chipLabel.implicitWidth + Style.space(12)
          height: chipLabel.implicitHeight + Style.space(5)
          radius: height / 2
          color: chip.active ? root.alpha(root.fg, 0.14) : root.alpha(root.fg, 0.05)

          Text {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.modelData
            color: chip.active ? root.fg : root.fainter
            font.family: root.face
            font.pixelSize: Style.font.caption
            font.bold: chip.active
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.picked(String(chip.modelData))
          }
        }
      }
    }
  }

  component BackedRow: Item {
    id: row
    property real share: 0
    property string label: ""
    property string value: ""

    height: Style.space(19)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.fg, 0.04)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * Math.max(0, Math.min(1, row.share))
      radius: Style.cornerRadius
      color: root.alpha(root.fg, 0.12)
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: rowValue.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: row.label
      color: root.fg
      elide: Text.ElideRight
      font.family: root.face
      font.pixelSize: Style.font.caption
    }

    Text {
      id: rowValue
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: row.value
      color: root.dim
      font.family: root.face
      font.pixelSize: Style.font.caption
    }
  }
}
