import QtQuick 2.0
import SddmComponents 2.0
import "Users.js" as Known

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  readonly property string fg: "#c0caf5"
  readonly property string accent: "#7aa2f7"
  readonly property string muted: "#565f89"
  readonly property string danger: "#f7768e"
  readonly property string font: "JetBrainsMono Nerd Font"

  property bool loginFailed: false
  property bool loading: false
  property bool showPassword: false
  property bool listOpen: false
  property string now: Qt.formatDateTime(new Date(), "HH:mm")
  property string today: Qt.formatDate(new Date(), "dddd, MMMM d, yyyy")

  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  function doLogin() {
    var user = username.text.trim()
    if (user === "" || password.text === "" || loading) return
    root.loginFailed = false
    root.loading = true
    sddm.login(user, password.text, root.sessionIndex)
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      root.now = Qt.formatDateTime(new Date(), "HH:mm")
      root.today = Qt.formatDate(new Date(), "dddd, MMMM d, yyyy")
    }
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loading = false
      root.loginFailed = true
      password.text = ""
      password.forceActiveFocus()
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  // Clock
  Column {
    anchors.top: parent.top
    anchors.topMargin: 40
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 4
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.now
      color: root.fg
      font.family: root.font
      font.pixelSize: 40
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.today
      color: root.muted
      font.family: root.font
      font.pixelSize: 16
    }
  }

  // Login form
  Column {
    anchors.centerIn: parent
    spacing: 24

    Image {
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
      z: 10
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: "user.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: userEntry.width
        height: userEntry.height

        Image {
          id: userEntry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        TextInput {
          id: username
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 48
          verticalAlignment: TextInput.AlignVCenter
          font.family: root.font
          font.pixelSize: 22
          color: root.fg
          selectionColor: root.accent
          text: userModel.lastUser
          clip: true
          enabled: !root.loading
          KeyNavigation.tab: password
          onTextChanged: root.loginFailed = false
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              password.forceActiveFocus()
              event.accepted = true
            }
          }
        }

        Text {
          text: "\uf078"
          color: chevronArea.containsMouse || root.listOpen ? root.accent : root.fg
          font.family: root.font
          font.pixelSize: 16
          anchors.right: parent.right
          anchors.rightMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          rotation: root.listOpen ? 180 : 0
          Behavior on rotation { NumberAnimation { duration: 120 } }
        }

        MouseArea {
          id: chevronArea
          width: 48
          height: parent.height
          anchors.right: parent.right
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.listOpen = !root.listOpen
        }

        Rectangle {
          visible: root.listOpen
          y: parent.height + 4
          width: parent.width
          height: Math.min(userList.count, 6) * 40 + 2
          color: root.color
          border.color: root.muted
          border.width: 1
          radius: 4
          clip: true

          ListView {
            id: userList
            anchors.fill: parent
            anchors.margins: 1
            model: [""].concat(Known.list)
            interactive: count > 6
            delegate: Rectangle {
              width: userList.width
              height: 40
              color: rowArea.containsMouse ? "#292e42" : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: index === 0 ? "+  New user" : modelData
                color: index === 0 ? root.accent : root.fg
                font.family: root.font
                font.pixelSize: 20
              }

              MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  username.text = index === 0 ? "" : modelData
                  root.listOpen = false
                  if (index === 0) username.forceActiveFocus()
                  else password.forceActiveFocus()
                }
              }
            }
          }
        }
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: root.showPassword ? 0 : Math.min(password.text.length, 17)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        Text {
          visible: root.showPassword
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.right: parent.right
          anchors.rightMargin: 48
          anchors.verticalCenter: parent.verticalCenter
          text: password.text
          elide: Text.ElideLeft
          color: root.fg
          font.family: root.font
          font.pixelSize: 22
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 48
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: root.font
          font.pixelSize: 24
          passwordCharacter: "\u2022"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          enabled: !root.loading
          KeyNavigation.backtab: username

          onTextChanged: root.loginFailed = false

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_F2) {
              root.showPassword = !root.showPassword
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.doLogin()
              event.accepted = true
            }
          }
        }

        Text {
          text: root.showPassword ? "\uf070" : "\uf06e"
          color: eyeArea.containsMouse || root.showPassword ? root.accent : root.fg
          font.family: root.font
          font.pixelSize: 18
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
          id: eyeArea
          width: 48
          height: parent.height
          anchors.right: parent.right
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.showPassword = !root.showPassword
        }
      }
    }

    // Reserved height so the layout does not jump when a message appears
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      height: 24
      text: root.loginFailed ? "Invalid username or password"
          : keyboard.capsLock ? "Caps Lock is on" : ""
      color: root.loginFailed ? root.danger : root.accent
      font.family: root.font
      font.pixelSize: 16
    }
  }

  // Machine name, bottom left
  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: 24
    text: "\uf108  " + sddm.hostName
    color: root.muted
    font.family: root.font
    font.pixelSize: 16
  }

  // Power buttons, bottom right
  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 24
    spacing: 28

    Text {
      visible: sddm.canReboot
      text: "\uf021  Restart"
      color: rebootArea.containsMouse ? root.accent : root.muted
      font.family: root.font
      font.pixelSize: 16
      MouseArea {
        id: rebootArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sddm.reboot()
      }
    }

    Text {
      visible: sddm.canPowerOff
      text: "\uf011  Shut down"
      color: offArea.containsMouse ? root.danger : root.muted
      font.family: root.font
      font.pixelSize: 16
      MouseArea {
        id: offArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sddm.powerOff()
      }
    }
  }

  // Loading overlay: the first login creates the home directory and takes a while
  Rectangle {
    anchors.fill: parent
    z: 100
    visible: root.loading
    color: root.color

    MouseArea { anchors.fill: parent }

    Column {
      anchors.centerIn: parent
      spacing: 28

      Image {
        source: "logo.png"
        width: Math.min(sourceSize.width, root.width * 0.8)
        height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
        fillMode: Image.PreserveAspectFit
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Rectangle {
        width: 320
        height: 4
        radius: 2
        color: "#292e42"
        clip: true
        anchors.horizontalCenter: parent.horizontalCenter

        Rectangle {
          id: bar
          width: 100
          height: parent.height
          radius: 2
          color: root.accent

          SequentialAnimation on x {
            running: root.loading
            loops: Animation.Infinite
            NumberAnimation { from: -100; to: 320; duration: 1100; easing.type: Easing.InOutQuad }
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Signing in as " + username.text.trim() + "…"
        color: root.fg
        font.family: root.font
        font.pixelSize: 18
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "The first sign-in can take a moment."
        color: root.muted
        font.family: root.font
        font.pixelSize: 14
      }
    }
  }

  Component.onCompleted: {
    if (username.text === "") username.forceActiveFocus()
    else password.forceActiveFocus()
  }
}
