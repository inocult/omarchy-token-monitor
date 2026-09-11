import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar icon and popup, built the same way as the network, bluetooth and
// tailscale panels: a `Panel` for the open/close lifecycle and IPC, a
// `BarIconButton` in the bar, and a `KeyboardPanel` anchored under it at
// Style.space(380) wide. Nothing novel on purpose -- it should be
// indistinguishable in behaviour from its neighbours, because it sits in a row
// with them.
Panel {
  id: root
  moduleName: "inocult.token-monitor"
  ipcTarget: "inocult.token-monitor"
  // manageIpc off because this adds refresh/wing on top of the standard five,
  // and a target only accepts one handler.
  manageIpc: false

  readonly property bool showCost: setting("showCost", true) !== false
  readonly property color barFg: bar ? bar.foreground : Color.foreground

  Usage { id: usage }

  readonly property bool alarming: {
    for (var i = 0; i < usage.limits.length; i++) if (usage.limits[i].alarming) return true
    return false
  }

  readonly property string label: {
    if (root.showCost && usage.priced) return Model.money(usage.todayCost)
    if (usage.todayTokens > 0) return Model.compactTokens(usage.todayTokens)
    return "--"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    bar: root.bar
    // The glyph carries the identity, the number carries the news. A vertical
    // bar has no room for both, so the number goes.
    text: root.vertical ? "󱚣" : "󱚣 " + root.label
    active: root.alarming
    tooltipText: Model.groupedTokens(usage.todayTokens) + " tokens today"
      + (usage.priced ? "\n" + Model.moneyExact(usage.todayCost) + " on this machine" : "")
      + (usage.devices.length > 1 ? "\n" + usage.devices.length + " machines" : "")

    onPressed: function (buttonCode) {
      // Left opens the popup like every other bar panel. Middle toggles the
      // always-on wing copy, which is the one thing the neighbours do not have.
      if (buttonCode === Qt.MiddleButton) root.toggleWing()
      else root.toggle()
    }
  }

  readonly property bool vertical: bar ? bar.vertical : false

  function toggleWing() {
    if (bar && typeof bar.run === "function") bar.run("omarchy-shell inocult.token-monitor-wing toggle")
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { usage.rescan(); return "ok" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) { flick.flick(0, -dy * Style.space(220)) }
      onCloseRequested: root.close()
      onActivateRequested: usage.rescan()
      // v switches pivot, r refreshes -- the panel's own keys, routed through
      // textKey because PanelKeyCatcher owns the key handling for every panel.
      onTextKey: function (text) {
        if (text === "v") body.toggleView()
        else if (text === "r") usage.rescan()
      }
    }

    Flickable {
      id: flick
      anchors.fill: parent
      contentHeight: body.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Content {
        id: body
        width: flick.width
        usage: usage
        showCost: root.showCost
        // Initial value, not a binding: a binding would snap the chips back to
        // the configured default the moment anything re-evaluated it.
        Component.onCompleted: view = String(root.setting("view", "machine"))
      }
    }
  }
}
