import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Rectangle {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    property string currentStyle: {
        if (pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings.indicatorStyle) {
            return pluginApi.pluginSettings.indicatorStyle;
        }
        return "boxes";
    }

    property string positionText: "-"

    implicitWidth: row.implicitWidth + Style.marginM * 2
    implicitHeight: Style.barHeight
    color: Style.capsuleColor
    radius: Style.radiusM

    function formatOutput(raw) {
        var parts = raw.split(",");
        if (parts.length !== 2) return "-";

        var current = parseInt(parts[0]);
        var total = parseInt(parts[1]);
        if (total === 0) return "-";

        var activeChar = "■";
        var inactiveChar = "□";
        var joiner = " ";

        if (currentStyle === "circles") {
            activeChar = "●";
            inactiveChar = "○";
        } else if (currentStyle === "braille") {
            activeChar = "⣿";
            inactiveChar = "⣀";
        } else if (currentStyle === "diamonds") {
            activeChar = "◆";
            inactiveChar = "◇";
        } else if (currentStyle === "stars") {
            activeChar = "★";
            inactiveChar = "☆";
        } else if (currentStyle === "triangles") {
            activeChar = "▲";
            inactiveChar = "△";
        } else if (currentStyle === "dashes") {
            activeChar = "━";
            inactiveChar = "─";
            joiner = "";
        } else if (currentStyle === "bars") {
            activeChar = "┃";
            inactiveChar = "│";
            joiner = "";
        } else if (currentStyle === "blocks") {
            activeChar = "█";
            inactiveChar = "░";
            joiner = "";
        }

        // Renamed from numbered_circles to "numbers"
        if (currentStyle === "numbers") {
            var cActive = ["❶","❷","❸","❹","❺","❻","❼","❽","❾","❿"];
            var cInactive = ["①","②","③","④","⑤","⑥","⑦","⑧","⑨","⑩"];
            var arrCirc = [];
            for (var c = 1; c <= total; c++) {
                var idx = c - 1;
                if (idx < 10) {
                    if (c === current) arrCirc.push(cActive[idx]);
                    else arrCirc.push(cInactive[idx]);
                } else {
                    if (c === current) arrCirc.push("(" + c + ")");
                    else arrCirc.push(c);
                }
            }
            return arrCirc.join(" ");
        }

        if (currentStyle === "dice") {
            var eInactive = ["⚀","⚁","⚂","⚃","⚄","⚅"];
            var arrEmoji = [];
            for (var e = 1; e <= total; e++) {
                var eIdx = e - 1;
                if (eIdx < 10) {
                    if (e === current) arrEmoji.push("■");
                    else arrEmoji.push(eInactive[eIdx]);
                } else {
                    if (e === current) arrEmoji.push("■");
                    else arrEmoji.push(e.toString());
                }
            }
            return arrEmoji.join(" ");
        }

        var visualArr = [];
        for (var k = 1; k <= total; k++) {
            if (k === current) {
                visualArr.push(activeChar);
            } else {
                visualArr.push(inactiveChar);
            }
        }
        return visualArr.join(joiner);
    }

    Process {
        id: positionScript
        command: ["bash", "-c", "$HOME/.config/noctalia/plugins/window-position-indicator/get_position.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "") {
                    root.positionText = root.formatOutput(this.text.trim());
                }
            }
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            positionScript.running = true;
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Style.marginS

        NText {
            text: root.positionText
            color: Color.mOnSurface
            pointSize: Style.fontSizeM
            bottomPadding: 3
        }
    }
}
