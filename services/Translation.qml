pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// ponytail: stub Translation service — Battery.qml needs translate() for one string.
// Real i18n + translator deferred to later stage.
// NOTE: cannot use method name 'tr' or 'qsTr' — reserved by QML engine.
Singleton {
    function translate(sourceText) { return sourceText }
}
