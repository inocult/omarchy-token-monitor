import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The dashboard itself, with no opinion about what it is mounted in.
//
// Used twice: as the body of the bar popup, and as the body of the wing
// surface. That is deliberate rather than tidy -- a popup and a wing that had
// separately-written layouts would drift apart the first time either was
// touched, and the point of both is to look like the rest of the bar.
//
// SCALE. Everything here is the same metric set the first-party panels use --
// Style.font.body / bodySmall / caption, Style.space(6..12) -- so it reads as a
// sibling of the network, bluetooth and tailscale popups rather than as a
// poster. An earlier version ran the type a step and a half larger on the
// theory that a wing is read from across the room; it was, correctly, "a little
// too big".
Column {
  id: root

  property var usage: null
  property bool showCost: true

  // Filled by whoever mounts this. The bar popup passes its on/off switch, the
  // way the network and bluetooth panels hang a control off their hero; the
  // wing and the window pass nothing and the hero simply has no trailing edge.
  property Component trailingControl: null

  // Which pivot is on screen. Both show the same facts; which one is useful
  // depends on the question. "machine" answers "what is that box running and
  // how close are its plans to the ceiling"; "subscription" answers "how much
  // of what I pay for is left, wherever it is signed in".
  property string view: "machine"
  function toggleView() { view = view === "machine" ? "subscription" : "machine" }

  spacing: Style.space(12)

  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color fainter: Qt.darker(fg, 1.9)
  readonly property color track: Style.selectedFillFor(fg, Color.accent)
  readonly property string face: Style.fontFamily

  // The line under the title, and the part of the header that moves.
  //
  // It cycles rather than concatenating, because the hero elides that line and
  // the trailing switch eats the width a full sentence would need -- the first
  // attempt read "2 MACHINES · 4 SUBSCRIPTIONS · UP…", which is three facts
  // truncated into none. One short clause at a time says more, and gives the
  // header the small liveness the network panel gets from its throughput.
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
    out.push(Model.compactTokens(usage.todayTokens) + " tokens today")

    // Whichever allowance is furthest along, which is the one worth knowing.
    var worst = null
    for (var i = 0; i < usage.limits.length; i++) {
      if (!worst || usage.limits[i].percent > worst.percent) worst = usage.limits[i]
    }
    if (worst && worst.percent > 0) {
      out.push(Model.shortLimit(worst.label).toLowerCase() + " " + Math.round(worst.percent * 100) + "% used")
    }
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

  // ----------------------------------------------------------------- header
  //
  // The same shape every other bar panel opens with: what this is, a line that
  // actually changes, and the control that turns it on.

  PanelHero {
    width: parent.width
    title: "Token Monitor"
    foreground: root.fg
    fontFamily: root.face
    meta: root.status
    // No detail pill. The hero's pill is a status badge -- a price wedged into
    // it sits mid-row, next to nothing it relates to, and demotes the one
    // number the panel exists to show. It belongs under the header, big.
    trailingControl: root.trailingControl

    iconComponent: Component {
      Text {
        text: "󱚣"
        color: root.fg
        font.family: root.face
        font.pixelSize: Style.font.display
      }
    }
  }

  // ------------------------------------------------------------------ today
  //
  // The two figures side by side rather than stacked: they are one fact read
  // two ways, and stacking them made the tokens look like a footnote to the
  // price. The token count is compact here -- the exact digits are on the
  // machine rows below, and at popup width the grouped form pushes the pair
  // apart until they stop reading as a pair.

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

    // What the two figures above are actually the sum of. With one machine
    // there is nothing to say -- they are this machine, obviously -- so the
    // line disappears rather than stating the obvious in every panel.
    Text {
      visible: root.usage && root.usage.hub
      width: parent.width
      text: {
        if (!root.usage) return ""
        var n = root.usage.devices.length
        var scope = "all " + n + " machines"
        return root.showCost && root.usage.todayCostEstimated
          ? scope + " · other machines' cost estimated" : scope
      }
      color: root.fainter
      elide: Text.ElideRight
      font.family: root.face
      font.pixelSize: Style.font.caption
    }
  }

  // ------------------------------------------------------------- the pivot

  Row {
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: [{ id: "machine", label: "By machine" }, { id: "subscription", label: "By subscription" }]
      delegate: Rectangle {
        required property var modelData
        readonly property bool active: root.view === modelData.id
        width: chipText.implicitWidth + Style.space(16)
        height: chipText.implicitHeight + Style.space(7)
        radius: height / 2
        color: active ? root.alpha(root.fg, 0.14) : root.alpha(root.fg, 0.05)

        Text {
          id: chipText
          anchors.centerIn: parent
          text: modelData.label
          color: parent.active ? root.fg : root.dim
          font.family: root.face
          font.pixelSize: Style.font.caption
          font.bold: parent.active
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.view = modelData.id
        }
      }
    }
  }

  // ---------------------------------------------------------- by machine
  //
  // Machine first, then everything that machine is signed into, each with its
  // own allowance bar. Nothing is added across machines: two boxes on two
  // different Claude accounts have two separate ceilings, and one merged
  // percentage would be true of neither.

  PanelSeparator { foreground: root.fg; visible: byMachine.visible }

  Column {
    id: byMachine
    width: parent.width
    spacing: Style.space(10)
    visible: root.view === "machine" && root.usage && root.usage.machines.length > 0

    PanelSectionHeader { text: "MACHINES"; foreground: root.fg }

    Repeater {
      model: root.usage ? root.usage.machines : []
      delegate: Column {
        id: box
        required property var modelData
        width: byMachine.width
        spacing: Style.space(6)

        // The machine itself: name, what it has burned, what that cost.
        Item {
          width: parent.width
          height: boxName.implicitHeight

          Text {
            id: boxName
            anchors.left: parent.left
            text: box.modelData.device + (box.modelData.local ? "  ·  this one" : "")
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
              + (box.modelData.stale ? "   " + Model.ago(box.modelData.updatedAt, root.usage.nowMs) : "")
            color: root.dim
            font.family: root.face
            font.pixelSize: Style.font.caption
          }
        }

        // and then what it is signed into.
        Repeater {
          model: box.modelData.subscriptions
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
              delegate: Item {
                required property var modelData
                width: sub.width
                height: Style.space(15)

                Text {
                  id: winLabel
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(78)
                  text: Model.shortLimit(modelData.label)
                  color: root.fainter
                  elide: Text.ElideRight
                  font.family: root.face
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: winValue
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(54)
                  horizontalAlignment: Text.AlignRight
                  text: Math.round(modelData.percent * 100) + "%"
                    + (modelData.resetsAt !== "" ? "  " + Model.untilReset(modelData.resetsAt, root.usage.nowMs) : "")
                  color: modelData.alarming ? Color.urgent : root.dim
                  font.family: root.face
                  font.pixelSize: Style.font.caption
                  font.bold: modelData.alarming
                }

                // The used-versus-allowance bar, inline with its window rather
                // than on a line of its own: at this width a stacked label,
                // bar and value costs three rows per limit and a machine with
                // three plans then needs a screen of its own.
                Rectangle {
                  anchors.left: winLabel.right
                  anchors.right: winValue.left
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
                    width: parent.width * Math.max(0, Math.min(1, modelData.percent))
                    color: modelData.alarming ? Color.urgent : root.fg
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------- subscriptions
  //
  // The same facts pivoted the other way: one row per plan, naming the machines
  // it is signed in on.

  PanelSeparator { foreground: root.fg; visible: subs.visible }

  Column {
    id: subs
    width: parent.width
    spacing: Style.space(8)
    visible: root.view === "subscription" && root.usage && root.usage.subscriptions.length > 0

    PanelSectionHeader { text: "SUBSCRIPTIONS"; foreground: root.fg }

    Repeater {
      model: root.usage ? root.usage.subscriptions : []
      delegate: Column {
        id: card
        required property var modelData
        width: subs.width
        spacing: Style.space(5)

        Item {
          width: parent.width
          height: Math.max(mark.height, planName.implicitHeight)

          // The same marks the first-party agents panel ships, copied in so the
          // plugin stays self-contained if that path ever moves.
          Image {
            id: mark
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            source: root.markFor(card.modelData.agent)
            visible: source !== ""
            width: Style.space(13); height: width
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            smooth: true
          }

          Text {
            id: planName
            anchors.left: mark.visible ? mark.right : parent.left
            anchors.leftMargin: mark.visible ? Style.space(7) : 0
            anchors.verticalCenter: parent.verticalCenter
            text: card.modelData.name
            color: root.fg
            font.family: root.face
            font.pixelSize: Style.font.body
            font.bold: true
          }

          // Plan beside the name rather than on a chip of its own line: at this
          // scale a chip is a row of its own, and "Max 20x" is what tells two
          // otherwise identical cards apart.
          Text {
            anchors.left: planName.right
            anchors.leftMargin: Style.space(6)
            anchors.right: where.left
            anchors.rightMargin: Style.space(8)
            anchors.baseline: planName.baseline
            visible: card.modelData.tier !== ""
            text: card.modelData.tier
            color: root.dim
            elide: Text.ElideRight
            font.family: root.face
            font.pixelSize: Style.font.bodySmall
          }

          // Which machines this plan is signed in on. One account used from two
          // desks is one subscription, so it names both on a single row rather
          // than appearing twice.
          Text {
            id: where
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: card.modelData.devices.join(" · ")
            color: root.fainter
            font.family: root.face
            font.pixelSize: Style.font.caption
          }
        }

        // No allowance to draw: say why rather than leaving a gap.
        Text {
          visible: card.modelData.limits.length === 0
          width: parent.width
          text: card.modelData.status !== "" ? card.modelData.status
            : (card.modelData.help !== "" ? card.modelData.help : "no limit data")
          color: root.fainter
          elide: Text.ElideRight
          font.family: root.face
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: card.modelData.limits
          delegate: Column {
            required property var modelData
            width: card.width
            spacing: Style.space(2)

            Item {
              width: parent.width
              height: limitLabel.implicitHeight

              Text {
                id: limitLabel
                anchors.left: parent.left
                anchors.right: limitValue.left
                anchors.rightMargin: Style.space(8)
                text: modelData.label
                color: root.dim
                elide: Text.ElideRight
                font.family: root.face
                font.pixelSize: Style.font.caption
              }

              Text {
                id: limitValue
                anchors.right: parent.right
                text: Math.round(modelData.percent * 100) + "%"
                  + (modelData.resetsAt !== "" ? "  " + Model.untilReset(modelData.resetsAt, root.usage.nowMs) : "")
                color: modelData.alarming ? Color.urgent : root.dim
                font.family: root.face
                font.pixelSize: Style.font.caption
                font.bold: modelData.alarming
              }
            }

            Meter {
              width: parent.width
              value: modelData.percent
              alarming: modelData.alarming
            }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- machines

  PanelSeparator { foreground: root.fg; visible: machines.visible }

  Column {
    id: machines
    width: parent.width
    spacing: Style.space(3)
    visible: root.view === "subscription" && root.usage && root.usage.devices.length > 1

    PanelSectionHeader { text: "MACHINES"; foreground: root.fg }

    Repeater {
      model: root.usage ? root.usage.devices : []
      delegate: BackedRow {
        required property var modelData
        width: machines.width
        share: modelData.tokens / Math.max(1, root.usage.devices[0].tokens)
        emphasis: modelData.local
        faded: modelData.stale
        // A machine that has not reported today is marked, not dropped: its
        // totals are still real, they are just not from today.
        label: modelData.device + (modelData.stale ? "   " + Model.ago(modelData.updatedAt, root.usage.nowMs) : "")
        value: Model.compactTokens(modelData.tokens)
          + (root.showCost && modelData.cost !== null ? "   " + Model.moneyExact(modelData.cost) : "")
      }
    }
  }

  // ------------------------------------------------------------ last 7 days

  PanelSeparator { foreground: root.fg; visible: week.visible }

  Column {
    id: week
    width: parent.width
    spacing: Style.space(3)
    visible: root.usage && root.usage.week.length > 0

    PanelSectionHeader { text: "LAST 7 DAYS"; foreground: root.fg }

    Repeater {
      model: root.usage ? root.usage.week : []
      delegate: Item {
        required property var modelData
        width: week.width
        height: Style.space(16)

        Text {
          id: dayLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(28)
          text: modelData.label
          color: modelData.today ? root.fg : root.fainter
          font.family: root.face
          font.pixelSize: Style.font.caption
          font.bold: modelData.today
        }

        Text {
          id: dayValue
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(44)
          horizontalAlignment: Text.AlignRight
          text: modelData.tokens > 0 ? Model.compactTokens(modelData.tokens) : "·"
          color: modelData.today ? root.fg : root.dim
          font.family: root.face
          font.pixelSize: Style.font.caption
          font.bold: modelData.today
        }

        Rectangle {
          anchors.left: dayLabel.right
          anchors.right: dayValue.left
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
            width: parent.width * Math.max(0, Math.min(1, modelData.ratio))
            color: modelData.today ? root.fg : root.alpha(root.fg, 0.5)
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- by model

  PanelSeparator { foreground: root.fg; visible: models.visible }

  Column {
    id: models
    width: parent.width
    spacing: Style.space(3)
    visible: root.usage && root.usage.models.length > 0

    PanelSectionHeader { text: "BY MODEL"; foreground: root.fg }

    Repeater {
      model: root.usage ? root.usage.models : []
      delegate: BackedRow {
        required property var modelData
        width: models.width
        share: modelData.tokens / Math.max(1, root.usage.models[0].tokens)
        label: modelData.model
        value: Model.compactTokens(modelData.tokens)
          + (root.showCost && modelData.cost !== null ? "   " + Model.moneyExact(modelData.cost) : "")
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

  Text {
    width: parent.width
    visible: root.showCost
    text: "estimated · rates as of " + (root.usage ? root.usage.ratesAsOf : "")
      + (root.usage && !root.usage.allTimeComplete ? " · some models unpriced" : "")
    color: root.fainter
    elide: Text.ElideRight
    font.family: root.face
    font.pixelSize: Style.font.caption
  }

  // A row with its bar painted behind the text rather than under it. These are
  // the lists that grow, and at popup width every row that costs two lines is a
  // row fewer on screen.
  component BackedRow: Item {
    id: row
    property real share: 0
    property string label: ""
    property string value: ""
    property bool emphasis: false
    property bool faded: false

    height: Style.space(19)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.fg, row.emphasis ? 0.07 : 0.04)
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
      color: row.faded ? root.fainter : root.fg
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

  // Rounded track filled to the percentage used -- the same shape as the meters
  // in the first-party panels, so the two read as one system.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false

    implicitHeight: Math.max(Style.space(3), Math.round(Style.spacing.controlHeight * 0.12))

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * Math.max(0, Math.min(1, meter.value))
      color: meter.alarming ? Color.urgent : root.fg
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }
}
