import QtQuick 2.6
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.5
import "pages"
import "cover"

ApplicationWindow {
    id: app
    initialPage: Component { LoginPage {} }
    cover: Component { CoverPage {} }
    allowedOrientations: defaultAllowedOrientations
    
    // Globale Variablen
    property bool loggedIn: false
    // Scheitert das Python-Modul (fehlendes Paket, Tippfehler), kommt sonst
    // nie ein Rueckruf und die Oberflaeche dreht sich ewig - darum sichtbar.
    property string pythonError: ""
    property string username: ""
    property var todayLessons: []
    
    // Funktion zum Aktualisieren des Stundenplans (für Cover etc.)
    function refreshTimetable() {
        if (!loggedIn) return
        py.getToday(function(result) {
            if (result && result.lessons) {
                var now = new Date()
                var today = now.getFullYear() * 10000 + 
                           (now.getMonth() + 1) * 100 + 
                           now.getDate()
                todayLessons = result.lessons.filter(function(l) {
                    return l.date === today
                })
            }
        })
    }
    property var weekLessons: []
    property string currentDate: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property var absenceReasons: []
    
    // Python Backend
    Python {
        id: python
        
        Component.onCompleted: {
            // Python Pfad setzen - Module liegen im Elternverzeichnis
            addImportPath('/usr/share/harbour-webuntis')
            
            // Backend importieren
            importModule('webuntis_classbook', function() {
                console.log("WebUntis classbook backend loaded")
                
                // Auto-Login versuchen
                call('webuntis_classbook.auto_login', [], function(success) {
                    if (success) {
                        app.loggedIn = true
                        console.log("Auto-login successful")
                        // Load absence reasons
                        python.loadAbsenceReasons()
                    }
                })
            })
        }
        
        onError: {
            console.log("Python error: " + traceback)
            app.pythonError = "Hintergrund nicht startklar:\n" + traceback
        }
        
        onReceived: {
            // Handle signals from Python
            if (data[0] === 'loginSuccess') {
                app.loggedIn = true
                app.username = data[1]
            } else if (data[0] === 'loginFailed') {
                app.loggedIn = false
            } else if (data[0] === 'loggedOut') {
                app.loggedIn = false
                app.username = ""
            } else if (data[0] === 'log') {
                console.log("[Python] " + data[1])
            }
        }
        
        // Hilfsfunktionen
        function searchSchools(query, callback) {
            call('webuntis_classbook.search_schools', [query], callback)
        }
        
        function parseSchoolUrl(text, loginName, callback) {
            call('webuntis_classbook.parse_school_url', [text, loginName], callback)
        }
        
        function setSchool(server, loginName, callback) {
            call('webuntis_classbook.set_school', [server, loginName], callback)
        }
        
        function doLogin(server, school, user, password, secret, save, callback) {
            call('webuntis_classbook.login', [server, school, user, password, secret, save], callback)
        }
        
        function setSecret(value, callback) {
            call('webuntis_classbook.set_secret', [value], callback)
        }
        
        function doLogout(callback) {
            call('webuntis_classbook.logout', [], callback)
        }
        
        function getToday(callback) {
            call('webuntis_classbook.get_today', [], callback)
        }
        
        function getWeek(callback) {
            call('webuntis_classbook.get_week', [], callback)
        }
        
        function getTimetable(startDate, endDate, callback) {
            call('webuntis_classbook.get_timetable', [startDate, endDate], callback)
        }
        
        function getTimetableFor(entityType, entityId, startDate, endDate, callback) {
            call('webuntis_classbook.get_timetable_for', [entityType, entityId, startDate, endDate], callback)
        }
        
        function getClassesList(callback) {
            call('webuntis_classbook.get_classes_list', [], callback)
        }
        
        function getTeachersList(callback) {
            call('webuntis_classbook.get_teachers_list', [], callback)
        }
        
        function getRoomsList(callback) {
            call('webuntis_classbook.get_rooms_list', [], callback)
        }
        
        function getStudentsList(callback) {
            call('webuntis_classbook.get_students_list', [], callback)
        }
        
        function getPeriodData(periodId, callback) {
            call('webuntis_classbook.get_period_data', [periodId], callback)
        }
        
        function getAbsenceReasons() {
            return app.absenceReasons
        }
        
        function loadAbsenceReasons(callback) {
            call('webuntis_classbook.get_absence_reasons', [], function(reasons) {
                app.absenceReasons = reasons
                if (callback) callback(reasons)
            })
        }
        
        function submitAbsences(periodId, absences, callback) {
            call('webuntis_classbook.submit_absences', [periodId, absences], callback)
        }
        
        function syncAbsences(periodId, absences, callback) {
            call('webuntis_classbook.sync_absences', [periodId, absences], callback)
        }
        
        function deleteAbsence(absenceId, callback) {
            call('webuntis_classbook.delete_absence', [absenceId], callback)
        }
        
        function editAbsence(absenceId, reasonId, startDatetime, endDatetime, text, callback) {
            call('webuntis_classbook.edit_absence', [absenceId, reasonId, startDatetime, endDatetime, text], callback)
        }
        
        function createLateness(periodId, studentId, reasonId, callback) {
            call('webuntis_classbook.create_lateness', [periodId, studentId, reasonId], callback)
        }
        
        function createLatenessWithTime(periodId, studentId, arrivalTime, reasonId, callback) {
            call('webuntis_classbook.create_lateness_with_time', [periodId, studentId, arrivalTime, reasonId], callback)
        }
        
        function fetchStudentImage(studentId, callback) {
            call('webuntis_classbook.fetch_student_image', [studentId], callback)
        }
        
        function submitTopic(periodId, text, callback) {
            call('webuntis_classbook.submit_topic', [periodId, text], callback)
        }
        
        function submitPeriodInfo(periodId, infoType, text, callback) {
            call('webuntis_classbook.submit_period_info', [periodId, infoType, text], callback)
        }
        
        function getClassregEvents(periodId, callback) {
            call('webuntis_classbook.get_classreg_events', [periodId], callback)
        }
        
        function getEventReasons(callback) {
            call('webuntis_classbook.get_event_reasons', [], callback)
        }
        
        function submitClassregEvent(periodId, studentIds, reasonId, text, callback) {
            // studentIds can be a single ID or an array
            // reasonId can be null/0 if no categories are configured
            call('webuntis_classbook.submit_classreg_event', [periodId, studentIds, reasonId, text], callback)
        }
        
        function getHomework(periodId, callback) {
            call('webuntis_classbook.get_homework', [periodId], callback)
        }
        
        function submitHomework(periodId, text, dueDate, remark, homeworkId, callback) {
            call('webuntis_classbook.submit_homework', [periodId, text, dueDate, remark, homeworkId], callback)
        }
        
        function deleteHomework(homeworkId, callback) {
            call('webuntis_classbook.delete_homework', [homeworkId], callback)
        }
        
        function testMobileApi(callback) {
            call('webuntis_classbook.test_mobile_api', [], callback)
        }
    }
}
