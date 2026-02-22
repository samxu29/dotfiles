import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    spacing: Style.marginM

    property var pluginApi: null
    property var pluginSettings: pluginApi ? pluginApi.pluginSettings : {}

    NText {
        text: "Indicator Style"
        font.bold: true
    }

    NText {
        text: "Note: Restart Noctalia Shell to apply changes."
        color: Color.mPrimary
        font.italic: true
        pointSize: Style.fontSizeS
    }

    Flow {
        Layout.fillWidth: true
        spacing: Style.marginS

        Repeater {
            model: ["numbers", "braille", "dice", "boxes", "circles", "diamonds", "stars", "triangles", "dashes", "bars", "blocks"]
            NButton {
                text: modelData.toUpperCase()

                color: root.pluginSettings.indicatorStyle === modelData ? Color.mPrimary : Color.mSurface
                textColor: root.pluginSettings.indicatorStyle === modelData ? "#FFFFFF" : Color.mOnSurface

                onClicked: {
                    root.pluginSettings.indicatorStyle = modelData
                    pluginApi.saveSettings()
                }
            }
        }
    }
}
