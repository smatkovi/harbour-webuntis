import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: selectPage
    allowedOrientations: Orientation.All
    
    property bool isLoading: false
    property var entityList: []
    property int selectedType: 0  // 0=none, 1=Klasse, 2=Lehrer, 4=Raum, 5=Schüler
    property string selectedTypeName: ""
    property string searchText: ""
    
    SilicaListView {
        id: listView
        anchors.fill: parent
        model: filteredList
        
        property var filteredList: {
            if (!searchText) return entityList
            var lower = searchText.toLowerCase()
            return entityList.filter(function(item) {
                return item.name.toLowerCase().indexOf(lower) !== -1
            })
        }
        
        header: Column {
            width: parent.width
            
            PageHeader {
                title: selectedType === 0 ? "Stundenplan wählen" : selectedTypeName
            }
            
            // Typ-Auswahl (nur wenn kein Typ gewählt)
            Column {
                width: parent.width
                visible: selectedType === 0
                spacing: Theme.paddingMedium
                
                SectionHeader {
                    text: "Was möchten Sie anzeigen?"
                }
                
                BackgroundItem {
                    width: parent.width
                    onClicked: loadEntities(1, "Klassen")
                    Label {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: "📚 Klassen"
                        font.pixelSize: Theme.fontSizeLarge
                    }
                }
                
                BackgroundItem {
                    width: parent.width
                    onClicked: loadEntities(2, "Lehrer*innen")
                    Label {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: "👩‍🏫 Lehrer*innen"
                        font.pixelSize: Theme.fontSizeLarge
                    }
                }
                
                BackgroundItem {
                    width: parent.width
                    onClicked: loadEntities(4, "Räume")
                    Label {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: "🚪 Räume"
                        font.pixelSize: Theme.fontSizeLarge
                    }
                }
                
                BackgroundItem {
                    width: parent.width
                    onClicked: loadEntities(5, "Schüler*innen")
                    Label {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: "🧑‍🎓 Schüler*innen"
                        font.pixelSize: Theme.fontSizeLarge
                    }
                }
            }
            
            // Suchfeld (nur wenn Typ gewählt)
            SearchField {
                id: searchField
                width: parent.width
                visible: selectedType !== 0
                placeholderText: "Suchen..."
                onTextChanged: searchText = text
                EnterKey.onClicked: focus = false
            }
        }
        
        PullDownMenu {
            MenuItem {
                visible: selectedType !== 0
                text: "Zurück zur Auswahl"
                onClicked: {
                    selectedType = 0
                    selectedTypeName = ""
                    entityList = []
                    searchText = ""
                }
            }
            MenuItem {
                text: "Mein Stundenplan"
                onClicked: {
                    pageStack.pop()
                }
            }
        }
        
        delegate: ListItem {
            id: entityItem
            width: parent.width
            contentHeight: Theme.itemSizeSmall
            
            property var entity: modelData
            
            onClicked: {
                // Öffne Stundenplan für diese Entität
                pageStack.push(Qt.resolvedUrl("TimetableViewPage.qml"), {
                    entityType: entity.type,
                    entityId: entity.id,
                    entityName: entity.name
                })
            }
            
            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: entity ? entity.name : ""
                truncationMode: TruncationMode.Fade
            }
        }
        
        ViewPlaceholder {
            enabled: !isLoading && selectedType !== 0 && listView.count === 0
            text: "Keine Einträge gefunden"
        }
        
        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: isLoading
            visible: isLoading
        }
        
        VerticalScrollDecorator {}
    }
    
    function loadEntities(type, typeName) {
        selectedType = type
        selectedTypeName = typeName
        isLoading = true
        entityList = []
        
        if (type === 1) {
            python.getClassesList(function(result) {
                isLoading = false
                entityList = result || []
            })
        } else if (type === 2) {
            python.getTeachersList(function(result) {
                isLoading = false
                entityList = result || []
            })
        } else if (type === 4) {
            python.getRoomsList(function(result) {
                isLoading = false
                entityList = result || []
            })
        } else if (type === 5) {
            python.getStudentsList(function(result) {
                isLoading = false
                entityList = result || []
            })
        }
    }
}
