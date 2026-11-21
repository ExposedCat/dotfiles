import QtQuick

SystemImage {
    id: root
    required property string name
    readonly property string adwaitaName: name === "weather-freezing-rain-symbolic" ? "weather-showers-symbolic"
        : name === "weather-none-available-symbolic" ? "weather-severe-alert-symbolic" : name

    iconSource: name
    fallbackIcon: adwaitaName !== name ? adwaitaName : ""
    fallbackSource: "file:///usr/share/icons/Adwaita/symbolic/status/" + adwaitaName + ".svg"
    sourceSize.width: Math.ceil(width)
    sourceSize.height: Math.ceil(height)
    layer.enabled: status === Image.Ready
}
