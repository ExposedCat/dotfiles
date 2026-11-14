import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Scope {
    id: root
    required property var shell
    property string selected: ""
    property int tick: 0
    property var fixturePlayer: ({identity: "Music", dbusName: "fixture", trackTitle: "A quiet afternoon", trackArtist: "Sample artist", trackAlbum: "Studio sessions", trackArtUrl: "", isPlaying: true, position: 75, length: 240, canControl: true, canTogglePlaying: true, canSeek: true, canGoPrevious: true, canGoNext: true})
    readonly property var players: shell.fixture ? (shell.fixtureData.players || [fixturePlayer]) : Mpris.players.values.filter(p => p !== null)
    readonly property var player: players.find(p => p && p.dbusName === selected) || players.find(p => p && p.isPlaying) || players[0] || null
    readonly property string title: player ? player.trackTitle || player.identity : "Nothing playing"
    readonly property string artist: player ? player.trackArtist || "" : "Play something in a media application"
    readonly property bool playing: !!(player && player.isPlaying)
    readonly property real position: { const t = tick; return player ? Math.max(0, player.position || 0) : 0; }
    readonly property real length: player ? Math.max(0, player.length || 0) : 0
    function action(name, value) {
        if (!player) return;
        if (shell.fixture) {
            shell.fixtureEvent("media", {action: name, value: value});
            if (name === "toggle") fixturePlayer = Object.assign({}, fixturePlayer, {isPlaying: !playing});
            if (name === "seek") fixturePlayer = Object.assign({}, fixturePlayer, {position: value});
            return;
        }
        if (name === "toggle" && player.canTogglePlaying) player.togglePlaying();
        else if (name === "next" && player.canGoNext) player.next();
        else if (name === "previous" && player.canGoPrevious) player.previous();
        else if (name === "seek" && player.canSeek) player.position = Math.max(0, Math.min(length, value));
    }
    function time(value) { value = Math.max(0, Math.floor(value)); return Math.floor(value / 60) + ":" + (value % 60).toString().padStart(2, "0"); }
    Timer { interval: 500; repeat: true; running: root.shell.panel === "media" && !root.shell.pillHidden; onTriggered: root.tick++ }
}
