import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.modules.settings

// A settings page: any Settings* controls work here.
SettingCard {
    title: "Hello"; icon: "󰋜"; tint: Atelier.accent
    SettingRow { label: "Hello from a plugin"; description: "This page lives in ~/.config/atelier/plugins/hello" }
}
