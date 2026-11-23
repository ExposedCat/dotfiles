import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Scope {
    id: root
    required property var shell
    property string selected: ""
    property var previousPlaying: []
    property var fixtureOverrides: ({})
    property int tick: 0
    property var fixturePlayer: ({identity: "Music", dbusName: "fixture", trackTitle: "A quiet afternoon", trackArtist: "Sample artist", trackAlbum: "Studio sessions", trackArtUrl: "", isPlaying: true, position: 75, length: 240, canControl: true, canTogglePlaying: true, canSeek: true, canGoPrevious: true, canGoNext: true})
    readonly property var players: (shell.fixture ? (shell.fixtureData.players || [fixturePlayer]) : Mpris.players.values)
        .filter(p => p && isAvailable(p))
    readonly property var playingPlayers: players.filter(p => isPlaying(p))
    readonly property var player: playingPlayers.find(p => p.dbusName === selected) || playingPlayers[0]
        || players.find(p => p.dbusName === selected) || players[0] || null
    onPlayingPlayersChanged: {
        const names = playingPlayers.map(p => p.dbusName);
        const started = names.filter(name => !previousPlaying.includes(name));
        if (started.length) selected = started[started.length - 1];
        previousPlaying = names;
    }
    onPlayerChanged: { if (!player && shell.panel === "media") shell.panel = ""; }
    function isAvailable(target) {
        if (target.isPlaying || target.playbackState === MprisPlaybackState.Paused
                || target.canTogglePlaying || target.canGoPrevious || target.canGoNext
                || (target.canSeek && target.length > 0)) return true;
        const trackId = String(target.metadata?.["mpris:trackid"] ?? "");
        const noTrack = "/org/mpris/MediaPlayer2/TrackList/NoTrack";
        // Qt can wrap the D-Bus object path in a QVariant.
        if (trackId) return trackId !== noTrack && !trackId.includes(`"${noTrack}"`);
        return !!(target.trackTitle || target.trackArtist || target.trackAlbum || target.trackArtUrl);
    }
    function isPlaying(target) { return !!(target && (fixtureOverrides[target.dbusName]?.isPlaying ?? target.isPlaying)); }
    function positionOf(target) {
        const refresh = tick;
        return target ? Math.max(0, fixtureOverrides[target.dbusName]?.position ?? target.position ?? 0) : 0;
    }
    function action(target, name, value) {
        if (!target || !players.includes(target)) return;
        if (name === "toggle" && !isPlaying(target)) selected = target.dbusName;
        if (shell.fixture) {
            shell.fixtureEvent("media", {player: target.dbusName, action: name, value: value});
            const next = Object.assign({}, fixtureOverrides);
            next[target.dbusName] = Object.assign({}, next[target.dbusName],
                name === "toggle" ? {isPlaying: !isPlaying(target)} : name === "seek" ? {position: value} : {});
            fixtureOverrides = next;
            return;
        }
        if (name === "toggle" && target.canTogglePlaying) target.togglePlaying();
        else if (name === "next" && target.canGoNext) target.next();
        else if (name === "previous" && target.canGoPrevious) target.previous();
        else if (name === "seek" && target.canSeek) target.position = Math.max(0, Math.min(target.length, value));
    }
    function time(value) { value = Math.max(0, Math.floor(value)); return Math.floor(value / 60) + ":" + (value % 60).toString().padStart(2, "0"); }
    Timer {
        interval: 250; repeat: true
        running: !!root.player && !!root.shell.pill && !root.shell.pill.hidden
            && (root.shell.panel === "media" || root.shell.pill.popupOpen)
        onTriggered: root.tick++
    }
}
