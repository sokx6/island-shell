import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    toggled: Idle.inhibit
    buttonIcon: "coffee"
    onClicked: {
        Idle.toggleInhibit()
    }
    StyledToolTip {
        text: Translation.translate("Keep system awake")
    }

}
