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

  // Bar widgets, unlike panels, get their settings handed to them and can write
  // them back through the shell -- the clock does the same to remember its
  // format. So the switch in the popup is durable: it survives a restart
  // instead of being a runtime flag that quietly resets.
  readonly property bool dashboardOn: {
    if (String(setting("mode", "")).toLowerCase() === "off") return false
    return setting("dashboard", true) !== false
  }
  readonly property string surface: {
    var legacy = String(setting("mode", "")).toLowerCase()
    var value = String(setting("surface", legacy === "window" ? "window" : "wing")).toLowerCase()
    return value === "window" ? "window" : "wing"
  }

  function writeSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value
    // `mode` was the old three-valued spelling of these two. Drop it on the
    // first write so it cannot keep overriding what the switch says.
    delete entry.mode
    entry.surface = root.surface
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
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
    // The switch is pinned, so the panel has to ask for room for both it and
    // the scrolling part. Measuring only the scrolling part -- which the first
    // version did -- makes the panel too short and clips its own footer.
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) { flick.flick(0, -dy * Style.space(220)) }
      onCloseRequested: root.close()
      onActivateRequested: usage.rescan()
      // v switches pivot, d toggles the dashboard, r refreshes -- routed
      // through textKey because PanelKeyCatcher owns key handling for every
      // panel in the bar.
      onTextKey: function (text) {
        if (text === "v") body.toggleView()
        else if (text === "d") root.writeSetting("dashboard", !root.dashboardOn)
        else if (text === "r") usage.rescan()
      }
    }

    Flickable {
      id: flick
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      contentHeight: body.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Content {
        id: body
        width: flick.width
        usage: usage
        showCost: root.showCost
        compact: true
        settingsSource: root.settings
        settingsWriter: function (key, value) { root.writeSetting(key, value) }
        // Initial value, not a binding: a binding would snap the chips back to
        // the configured default the moment anything re-evaluated it.
        Component.onCompleted: view = String(root.setting("view", "machine"))

        // Toggle is stateless by design -- it reports a click and the consumer
        // flips the value -- so this writes the setting and lets the dashboard
        // plugin pick it up, rather than keeping a second copy of the truth in
        // the bar. Verified live: the window comes and goes with no restart.
        trailingControl: Component {
          ToggleSwitch {
            checked: root.dashboardOn
            foreground: root.barFg
            onToggled: root.writeSetting("dashboard", !root.dashboardOn)
          }
        }
      }
    }
  }
}
