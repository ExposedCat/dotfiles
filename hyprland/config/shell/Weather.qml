import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell

    property var location: null
    property var forecast: null
    property double fetchedAt: 0
    property bool unavailable: false
    property bool saveFailed: false
    readonly property var current: forecast?.current ?? null
    readonly property var day: condition(current?.weather_code, current?.is_day !== 0)
    readonly property bool loading: forecastRequest.running
    readonly property string summary: !location ? "Set weather location" : current
        ? day.label + "  ·  " + temperature(current.temperature_2m)
        : loading ? "Loading weather…" : "Weather unavailable"

    property var requestedLocation: null
    property string searchedQuery: ""
    property var places: []
    property bool searchFailed: false
    readonly property bool searching: searchRequest.running
    readonly property int refreshInterval: 15 * 60 * 1000
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dotfiles/hyprland"

    function condition(code, daylight) {
        let label = "Unknown conditions";
        let icon = "none-available";
        switch (code) {
        case 0: label = "Clear"; icon = daylight ? "clear" : "clear-night"; break;
        case 1: label = "Mostly clear"; icon = daylight ? "few-clouds" : "few-clouds-night"; break;
        case 2: label = "Partly cloudy"; icon = daylight ? "few-clouds" : "few-clouds-night"; break;
        case 3: label = "Overcast"; icon = "overcast"; break;
        case 45: label = "Fog"; icon = "fog"; break;
        case 48: label = "Freezing fog"; icon = "fog"; break;
        case 51: case 53: case 55: label = "Drizzle"; icon = "showers-scattered"; break;
        case 56: case 57: label = "Freezing drizzle"; icon = "freezing-rain"; break;
        case 61: case 63: case 65: label = "Rain"; icon = "showers"; break;
        case 66: case 67: label = "Freezing rain"; icon = "freezing-rain"; break;
        case 71: case 73: case 75: case 77: label = "Snow"; icon = "snow"; break;
        case 80: case 81: case 82: label = "Rain showers"; icon = "showers-scattered"; break;
        case 85: case 86: label = "Snow showers"; icon = "snow"; break;
        case 95: case 97: label = "Thunderstorms"; icon = "storm"; break;
        case 96: case 99: label = "Thunder and hail"; icon = "storm"; break;
        }
        return {label: label, icon: "weather-" + icon + "-symbolic"};
    }

    function rounded(value, unit) {
        return Number.isFinite(value) ? String(Math.round(value)).replace("-", "−") + unit : "—";
    }

    function temperature(value) { return rounded(value, "°C"); }

    function region(place, includeCounty) {
        return [includeCounty ? place.admin2 : "", place.admin1, place.country].filter((part, index, parts) =>
            part && part !== place.name && parts.indexOf(part) === index).join(", ");
    }

    function validPlace(place) {
        return typeof place?.name === "string" && place.name.length > 0
            && Number.isFinite(place.latitude) && Math.abs(place.latitude) <= 90
            && Number.isFinite(place.longitude) && Math.abs(place.longitude) <= 180;
    }

    function validForecast(data) {
        return !!data?.current && Array.isArray(data.daily?.time) && data.daily.time.length > 0;
    }

    function request(url) {
        return ["/usr/bin/curl", "--disable", "--fail", "--silent", "--connect-timeout", "5",
            "--max-time", "12", "--max-filesize", "262144", "--proto", "=https", url];
    }

    function findPlaces(query) {
        if (searching || query.length < 2) return;
        searchedQuery = query;
        places = [];
        searchFailed = false;
        if (shell.fixture) {
            places = (shell.fixtureData.weather?.places || []).filter(place =>
                validPlace(place) && (place.name + " " + region(place, true)).toLowerCase().includes(query.toLowerCase()));
            return;
        }
        searchRequest.command = request("https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&name=" + encodeURIComponent(query));
        searchRequest.running = true;
    }

    function selectPlace(place) {
        if (!validPlace(place)) return;
        const next = {id: place.id, name: place.name, admin1: place.admin1, country: place.country,
            latitude: place.latitude, longitude: place.longitude};
        if (location?.id === next.id && location?.latitude === next.latitude && location?.longitude === next.longitude) {
            refresh();
            return;
        }
        location = next;
        forecast = null;
        fetchedAt = 0;
        unavailable = false;
        persist();
        refresh();
    }

    function refresh(force) {
        if (!location || loading || (!force && Date.now() - fetchedAt < refreshInterval)) return;
        if (shell.fixture) {
            applyForecast(shell.fixtureData.weather?.forecasts?.[location.id]);
            return;
        }
        nextRefresh.stop();
        requestedLocation = location;
        forecastRequest.command = request(
            "https://api.open-meteo.com/v1/forecast?latitude=" + location.latitude + "&longitude=" + location.longitude
            + "&timezone=auto&forecast_days=7"
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,is_day,weather_code"
            + "&daily=weather_code,temperature_2m_min,temperature_2m_max,precipitation_probability_max");
        forecastRequest.running = true;
    }

    function applyForecast(data) {
        unavailable = !validForecast(data);
        if (!shell.fixture) scheduleRefresh(unavailable ? 5 * 60 * 1000 : refreshInterval);
        if (unavailable) return;
        forecast = data;
        fetchedAt = Date.now();
        persist();
    }

    function persist() {
        if (!shell.fixture && !stateDirectory.running) stateDirectory.running = true;
    }

    function scheduleRefresh(delay) {
        nextRefresh.interval = delay;
        nextRefresh.restart();
    }

    FileView {
        id: saved
        path: root.shell.fixture ? "" : root.stateDir + "/weather.json"
        atomicWrites: true
        blockLoading: true
        blockWrites: true
        printErrors: false
        onSaved: root.saveFailed = false
        onSaveFailed: root.saveFailed = true
    }
    Process {
        id: stateDirectory
        command: ["/usr/bin/mkdir", "-p", root.stateDir]
        onExited: code => {
            if (code === 0) saved.setText(JSON.stringify({
                location: root.location, forecast: root.forecast, fetchedAt: root.fetchedAt
            }));
            else root.saveFailed = true;
        }
    }
    Process {
        id: forecastRequest
        stdout: StdioCollector { id: forecastOutput }
        onExited: code => {
            // A response can arrive after the selected city has changed.
            if (root.requestedLocation !== root.location) {
                Qt.callLater(root.refresh);
                return;
            }
            try { root.applyForecast(code === 0 ? JSON.parse(forecastOutput.text) : null); }
            catch (error) { root.applyForecast(null); }
        }
    }
    Process {
        id: searchRequest
        stdout: StdioCollector { id: searchOutput }
        onExited: code => {
            try {
                if (code !== 0) throw Error("Location search failed");
                const data = JSON.parse(searchOutput.text);
                root.places = (data.results || []).filter(root.validPlace);
            } catch (error) { root.searchFailed = true; }
        }
    }
    Timer {
        id: nextRefresh
        onTriggered: root.refresh(true)
    }
    Component.onCompleted: {
        if (shell.fixture) {
            if (shell.fixtureData.weather?.location) selectPlace(shell.fixtureData.weather.location);
            return;
        }
        try {
            const data = JSON.parse(saved.text());
            if (validPlace(data.location)) {
                location = data.location;
                if (validForecast(data.forecast)) {
                    forecast = data.forecast;
                    fetchedAt = Number(data.fetchedAt) || 0;
                }
            }
        } catch (error) { /* A fresh profile has no selected location. */ }
        const age = Math.max(0, Date.now() - fetchedAt);
        if (forecast && age < refreshInterval) scheduleRefresh(refreshInterval - age);
        else refresh();
    }
}
