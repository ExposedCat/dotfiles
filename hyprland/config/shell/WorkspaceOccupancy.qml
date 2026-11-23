import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root
    property bool enabled: true
    property var emptyOutputs: []
    property int revision: 0
    property int queryRevision: -1

    function refresh() {
        if (enabled) {
            revision++;
            settle.restart();
        }
    }

    onEnabledChanged: refresh()
    Component.onCompleted: refresh()
    Connections {
        target: Hyprland
        enabled: root.enabled
        function onRawEvent(event) {
            if (["workspacev2", "openwindow", "closewindow", "movewindowv2", "activespecialv2",
                 "moveworkspacev2", "monitoraddedv2", "monitorremoved", "configreloaded"].includes(event.name))
                root.refresh();
        }
    }
    Timer {
        id: settle
        interval: 35
        onTriggered: {
            if (!root.enabled || query.running) return;
            root.queryRevision = root.revision;
            query.running = true;
        }
    }
    Process {
        id: query
        // A move can reach Quickshell before it knows the destination workspace.
        // Read the active workspace and its count together from the compositor.
        command: ["hyprctl", "repl", `
            local outputs = {}
            for _, monitor in ipairs(hl.get_monitors()) do
                local workspace = hl.get_active_workspace(monitor)
                if workspace and workspace.windows == 0 and not hl.get_active_special_workspace(monitor) then
                    outputs[#outputs + 1] = monitor.name
                end
            end
            return table.concat(outputs, string.char(10))
        `]
        stdout: StdioCollector { id: result }
        onExited: code => {
            if (root.queryRevision !== root.revision) settle.restart();
            else root.emptyOutputs = code === 0 ? result.text.trim().split("\n") : [];
        }
    }
}
