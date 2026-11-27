import QtQuick

ShellTheme {
    background: "#27211e"
    surface: "#423d3a"
    hover: "#625b56"
    border: "#8b817a"
    text: "#ffffff"
    secondary: "#dddddf"
    accent: "#f4f4f5"
    green: "#b8c79b"
    red: "#ed9c87"
    amber: "#e4c393"
    readonly property int overviewInset: 21
    readonly property real overviewRadius: 31.25
    readonly property int overviewGap: 14
    readonly property real overviewTileRadius: 21.25
    readonly property int overviewControlSize: 54
    readonly property int overviewControlPadding: 9
    readonly property int overviewControlGap: 6
    readonly property real overviewControlRadius: 16.25
    readonly property int overviewControlIconSize: 23
    readonly property color glassTop: "#e53b302a"
    readonly property color glassBottom: "#ed241e1b"
    readonly property color overviewRim: "#16fff1e4"
    readonly property color overviewHighlight: "#0cfff8ef"
    readonly property color overviewShadow: "#3e130a07"
    readonly property color overviewGlow: "#66483a"
    readonly property color overviewMiddle: "#3b2e28"
    readonly property color overviewBase: "#29211e"
    readonly property var overviewGradient: [ellipticalWash([0.42, -0.34], null, 0.49, 0.87)]
    readonly property var popupGradients: ({
        mixer: [linearWash(137, 0.30, 0.88, 0.93)],
        weather: [ellipticalWash([0.35, 0.09], [0.98, 0.78], 0.40, 0.83, 0.71)],
        calendar: [ellipticalWash([0.45, -0.21], [0.97, 1.10], 0.42, 0.83)],
        ethernet: [ellipticalWash([0.04, -0.14], [1.30, 1.64], 0.44, 0.95)],
        vpn: [ellipticalWash([0.04, -0.14], [1.30, 1.64], 0.44, 0.95)],
        media: [linearWash(265, 0.32, 0.87, 0.83)],
        power: [linearWash(0, 0.51, 1, 0.66)],
        bluetooth: [{
            // Reveal more of the wash as devices appear, without stretching it.
            angle: 180, referenceHeight: 340, strength: 0.76,
            stops: [[0, overviewBase], [0.16, overviewMiddle], [0.33, overviewGlow],
                [0.43, overviewGlow], [0.64, overviewMiddle], [0.94, overviewBase]]
        }],
        system: [
            ellipticalWash([0.91, 0.10], [0.92, 0.69], 0.39, 0.91),
            ellipticalWash([0.14, 0.84], [0.75, 0.49], 0.48, 0.98, 0.59, true)
        ],
        notifications: [linearWash(106, 0.34, 0.89, 0.70)],
        launcher: [linearWash(180, 0.25, 0.70, 0.83)],
        clipboard: [linearWash(47, 0.46, 0.92, 0.81)],
        tray: [ellipticalWash([0.50, -0.10], [1.45, 0.96], 0.45, 0.90, 0.84)],
        share: [
            ellipticalWash([0.74, 1.08], [1.03, 0.83], 0.43, 0.93, 0.80),
            ellipticalWash([0.31, -0.10], [1.20, 0.55], 0.49, 1, 0.45, true)
        ],
        apps: [ellipticalWash([-0.11, 0.18], [1.14, 0.93], 0.41, 0.86, 0.92)],
        access: [linearWash(118, 0.25, 0.81, 0.61)],
        credentials: [ellipticalWash([0.48, 0.45], [1.10, 0.73], 0.37, 0.85, 0.69)],
        authentication: [linearWash(83, 0.38, 0.87, 0.67)]
    })
    readonly property color overviewInk: "#fff7f1"
    readonly property color overviewSecondary: "#d5c3b8"
    readonly property color overviewAccent: "#edac8d"
    readonly property color overviewDot: "#8cc9b3a6"
    readonly property color overviewControls: "#88201815"
    readonly property color overviewButton: "#12fff2e4"
    readonly property color overviewButtonHover: "#20fff2e4"
    readonly property color overviewPowerFill: "#268c4433"
    readonly property color overviewPowerInk: "#f1b69e"
    readonly property color weatherTileTop: "#684735"
    readonly property color weatherTileMiddle: "#50372d"
    readonly property color weatherTileBottom: "#4b342c"
    readonly property var weatherGlassStops: [[0, weatherTileTop], [0.66, weatherTileMiddle], [1, weatherTileBottom]]
    readonly property var compactGlassStops: [[0, "#ed3b302a"], [0.66, "#ed332923"], [1, "#ed2e2520"]]
    readonly property color glassHighlight: "#20f8d3b8"
    readonly property var notificationGlassStops: [
        [[0, "#30241e"], [0.66, "#291f1a"], [1, "#231a16"]],
        [[0, "#2b201a"], [0.66, "#241914"], [1, "#1f1712"]],
        [[0, "#261b15"], [0.66, "#201610"], [1, "#1b130e"]]
    ]
    readonly property var selectedGlassStops: [[0, "#604439"], [0.66, "#50362c"], [1, "#432e25"]]
    readonly property color selectedGlassInk: "#ffe0cf"
    readonly property color weatherAccent: "#ffe2cf"
    readonly property color weatherCondition: "#ffe7d4"

    function linearWash(angle, middle, edge, strength): var {
        return {angle, strength, stops: [[0, overviewGlow], [middle, overviewMiddle], [edge, overviewBase]]};
    }

    function ellipticalWash(center, radii, middle, edge, strength = 1, fadeOut = false): var {
        return {center, radii, strength, stops: [[0, overviewGlow], [middle, overviewMiddle],
            [edge, fadeOut ? Qt.alpha(overviewMiddle, 0) : overviewBase]]};
    }

    function weatherIconColor(name): color {
        if (name.includes("-night")) return "#c8bdf2";
        if (name.includes("clear") || name.includes("few-clouds")) return "#ffd491";
        if (name.includes("snow")) return "#d9edff";
        if (name.includes("showers") || name.includes("rain")) return "#9dcaf2";
        if (name.includes("storm")) return "#e6bbf0";
        return "#d8cbd2";
    }
}
