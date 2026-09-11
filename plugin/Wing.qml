import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The always-on copy, pinned to a wing.
//
// Same Content.qml the bar popup uses, at the same scale, so this is that panel
// left open on a screen you glance at rather than a second design. Earlier this
// had a type scale of its own, on the theory that a wing is read from further
// away; it just looked oversized next to everything else on the bar.
//
// A layer surface rather than a window, which is also why the plugin exists:
// the Electron app this replaced declared a maximum window size smaller than a
// portrait wing's tile, so the compositor could not tile it and floated it half
// off the screen. A shell surface has no such argument to have.
//
// Toggle with:  omarchy-shell inocult.token-monitor-wing toggle
// or middle-click the bar icon. Set heightPercent below 100 and it reserves
// only the top of the wing, leaving the rest tileable.
Item {
  id: root

  // Injected by the host for panel-kind plugins. Unlike bar widgets, a panel
  // gets no `settings` of its own, so preferences are read back out of
  // shell.json through this.
  property var shell: null
  property var manifest: null

  // The host hands a panel plugin a `shell` facade -- and that facade has
  // barConfig and idleConfig on it, NOT shellConfig. An earlier version read
  // shell.shellConfig, which is simply undefined, so every setting here
  // silently fell back to its default and no amount of `omarchy bar set` moved
  // anything. Nothing errors when you do that; it just quietly does nothing.
  //
  // barConfig is the `bar` subtree of shell.json, which is exactly where
  // `omarchy bar set inocult.token-monitor <key> <value>` writes, so this reads
  // back what that command writes.
  readonly property var config: {
    var found = ({})
    var doc = shell && shell.barConfig ? shell.barConfig : null
    var layout = doc && doc.layout ? doc.layout : ({})
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]] || []
      for (var e = 0; e < entries.length; e++) {
        if (entries[e] && String(entries[e].id) === "inocult.token-monitor") found = entries[e]
      }
    }
    return found
  }

  function setting(name, fallback) {
    var value = config ? config[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property string wantedMonitor: String(setting("monitor", ""))
  // 0 means "as tall as the content needs", which is the default and almost
  // always the right answer: the dashboard then reserves exactly its own height
  // and the rest of the workspace is ordinary tiling space. 100 gives it the
  // whole wing; anything between pins it to that share.
  readonly property int heightPercent: Math.max(0, Math.min(100, Number(setting("heightPercent", 0))))
  readonly property bool fullWing: heightPercent >= 100
  readonly property bool showCost: setting("showCost", true) !== false
  // wing   -- a layer-shell strip pinned to a screen, reserving its own height
  // window -- an ordinary window, tiled by Hyprland like anything else
  // off     -- neither; the bar popup is still there
  //
  // Both are this same process and this same plugin. A separate application
  // was never needed: Quickshell will hand you a real xdg-toplevel
  // (FloatingWindow) just as readily as a layer surface, and the only reason
  // the first version was layer-only is that a layer surface sidesteps tiling
  // entirely -- which mattered when the thing being replaced could not be
  // tiled. Nothing here declares a maximumSize, which is precisely the mistake
  // that made the Electron app untileable.
  readonly property string mode: {
    var value = String(setting("mode", setting("wing", true) !== false ? "wing" : "off")).toLowerCase()
    return value === "window" || value === "off" ? value : "wing"
  }

  property bool shown: true

  // No connector configured: take the tallest portrait screen, which on a desk
  // with wings is a wing and on a desk without one is nothing worth pinning to.
  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    var best = null
    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (!screen || !screen.name || screen.width <= 0 || screen.height <= 0) continue
      if (wantedMonitor !== "") {
        if (String(screen.name) === wantedMonitor) return screen
        continue
      }
      if (screen.height <= screen.width) continue
      if (!best || screen.height > best.height) best = screen
    }
    return best
  }

  Usage { id: usage }

  // What the dashboard actually needs, clamped so a very long fleet scrolls
  // instead of trying to reserve more screen than exists.
  readonly property real contentHeight: {
    var padding = 2 * Style.spacing.panelPadding
    var wanted = body.implicitHeight + padding
    var ceiling = targetScreen ? targetScreen.height * 0.92 : wanted
    return Math.max(Style.space(120), Math.min(ceiling, wanted))
  }

  IpcHandler {
    target: "inocult.token-monitor-wing"
    function open(): void { root.shown = true }
    function close(): void { root.shown = false }
    function show(): void { root.shown = true }
    function hide(): void { root.shown = false }
    function toggle(): void { root.shown = !root.shown }
    function refresh(): string { usage.rescan(); return "ok" }
  }

  PanelWindow {
    id: wing

    // remapGuard, not optional: Hyprland leaves an already-mapped layer surface
    // at its old global position when its monitor moves in the layout, so a
    // wing that is re-placed by a dock event keeps drawing at the old offset --
    // or off-screen entirely -- until something unmaps and remaps it.
    visible: root.shown && root.mode === "wing" && !!root.targetScreen && !remapGuard.remapping
    screen: root.targetScreen

    // FULL WING (100%): all four edges, reserve NOTHING. A layer surface fills
    // whatever the surfaces that DID reserve left over, so this lands under the
    // bar on its own. Asking to reserve here instead leaves nothing for anyone
    // else and pushes the bar clean off the bottom (864x26 at 0,1536, measured).
    //
    // ANYTHING ELSE: three edges and a real exclusive zone, so the strip is
    // reserved and Hyprland tiles the workspace's windows in what is left --
    // properly, with gaps, as though the dashboard were a window of its own.
    // That is the difference between "takes too much space" and "takes its
    // space": a zero zone means every window on the wing is drawn underneath
    // this and you never see it.
    anchors { top: true; left: true; right: true; bottom: root.fullWing }
    implicitHeight: root.fullWing ? 0
      : (root.heightPercent > 0
        ? Math.round((root.targetScreen ? root.targetScreen.height : 0) * root.heightPercent / 100)
        : root.contentHeight)

    //   Auto   -- reserve my whole height; at 100% that is the entire output.
    //   Ignore -- zone -1: reserve nothing AND ignore everyone else's zones, so
    //             the dashboard paints straight over the bar.
    //   Normal -- an explicit zone, which is the only one of the three that
    //             lets us say "reserve exactly this much".
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: root.fullWing ? 0 : wing.implicitHeight
    color: Color.popups.background

    WlrLayershell.namespace: "inocult-token-monitor"
    // Top, not Bottom. On Bottom a dashboard is painted under every window, so
    // on a wing that still has anything tiled on it you see the window and not
    // the dashboard.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    ScreenMoveRemap { id: remapGuard; window: wing }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.topMargin: Style.spacing.panelPadding
      anchors.bottomMargin: Style.spacing.panelPadding
      anchors.leftMargin: Style.spacing.panelPadding
      anchors.rightMargin: Style.spacing.panelPadding
      contentHeight: body.implicitHeight + body.y
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

        // Only centred when the dashboard owns the whole wing. Sized to its
        // content there is nothing to centre, and centring against a height
        // derived from this item's own height would be a binding loop.
        y: root.fullWing ? Math.max(0, (flick.height - implicitHeight) / 2) : 0
      }
    }
  }

  // An ordinary window. Hyprland tiles it with everything else -- no exclusive
  // zone, no layer, no special case. Give it a home with a window rule on the
  // title, since every Quickshell window shares one app id:
  //
  //   o.window({ title = "^Token Monitor$" }, { workspace = "1 silent" })
  FloatingWindow {
    id: windowed
    visible: root.shown && root.mode === "window"
    title: "Token Monitor"
    color: Color.popups.background

    // A starting size, not a constraint. minimumSize is left at its default and
    // maximumSize is never set: a window that tells the compositor it refuses
    // to grow past some size is a window the compositor cannot tile, which is
    // the whole reason this plugin exists.
    implicitWidth: Style.space(430)
    implicitHeight: Style.space(620)

    Flickable {
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      contentHeight: windowBody.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Content {
        id: windowBody
        width: parent.width
        usage: usage
        showCost: root.showCost
        Component.onCompleted: view = String(root.setting("view", "machine"))
      }
    }
  }
}
