import QtQuick
import Quickshell
Scope {
    id: test
    property var app: null
    property real compact: 0
    property real clockX: 0
    property var slider: null
    property var day: null
    property var number: null
    property int step: 0
    function check(v,m) { if(!v) { console.error("INTERACTION FAIL:",m);Qt.exit(1);throw Error(m); } }
    function all(item) { let a=[];for(const c of item.children||[]) {a.push(c);a=a.concat(all(c));}return a; }
    function clock() { return all(app.pill.contentItem).find(c=>typeof c.text==="string" && /^\d\d:\d\d$/.test(c.text)); }
    function stableClock() { const c=clock();check(c.mapToItem(app.pill.contentItem,0,0).x===clockX && app.pill.pillGeometry.height===40,"Feedback moved or replaced the clock"); }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"),"Private fixture required");
        const c=Qt.createComponent("file:"+Quickshell.env("DOTFILES_SHELL_SOURCE")+"/shell.qml");
        check(c.status===Component.Ready,c.errorString());app=c.createObject(test);advance.start();
    }
    Timer {
        id:advance;interval:600;repeat:true
        onTriggered: {
            switch(test.step++) {
            case 0:
                test.compact=test.app.pill.pillGeometry.width;test.clockX=test.clock().mapToItem(test.app.pill.contentItem,0,0).x;
                test.app.osd.showAudio(false,0.67,false);break;
            case 1:
                test.stableClock();test.check(test.app.pill.pillGeometry.width>test.compact && test.app.pill.pillGeometry.width-test.compact<=110,"Volume stretched farther than its progress bar needs");
                test.check(test.all(test.app.pill.contentItem).filter(c=>String(c).startsWith("PillBackground_")).length===1,"Feedback created an additional pill background");
                test.app.osd.showWorkspace("2");break;
            case 2:
                test.stableClock();test.check(test.app.emberTarget && test.app.pill.ember.dock===test.app.emberTarget && test.app.emberTarget.height===7,"Workspace feedback did not carry the red indicator");
                test.app.osd.showWorkspace("3");break;
            case 3:
                test.stableClock();test.check(test.app.pill.ember.dock===test.app.emberTarget,"Workspace feedback did not finish its switch animation");
                test.app.osd.showBrightness("DP-3",72,100);break;
            case 4:
                test.stableClock();test.app.toggle("mixer");break;
            case 5:
                test.slider=test.all(test.app.pill.activePane).filter(c=>c.handle && c.backendValue!==undefined).slice(-1)[0];
                test.app.pill.activePane.follow(test.slider);test.slider.forceActiveFocus();break;
            case 6:
                test.app.brightness.setLevel("DP-3",0.42);test.app.brightness.setLevel("DP-3",0.83);break;
            case 7:
                test.check(test.all(test.app.pill.activePane).includes(test.slider) && test.slider.activeFocus,"Saving brightness recreated the control or lost focus");
                test.check(test.app.pill.activePane.focusedSlider===test.slider && test.app.emberTarget===test.slider.emberSlot && test.app.pill.ember.dock===test.slider.emberSlot,"Saving brightness restarted the bead animation");
                test.app.toggle("notifications");break;
            case 8:
                test.app.agenda.selectDate(new Date(test.app.clock.date.getTime()+86400000));
                test.day=test.all(test.app.pill.contentItem).find(c=>c.selected && c.modelData instanceof Date);
                test.number=test.all(test.day).find(c=>c.text===String(test.day.modelData.getDate()) && c.color);
                test.check(String(test.number.color)==="#ffffff" && !test.day.emberSlot.landed,"Calendar darkened its number before landing");break;
            case 9:
                test.check(test.day.emberSlot.landed && String(test.number.color)!=="#ffffff","Calendar did not change contrast after landing");
                console.warn("INTERACTION PASS: one connected pill, compact progress feedback, stationary clock, red workspace OSD, stable brightness controls/focus/marker, calendar landing contrast");Qt.quit();
            }
        }
    }
    Timer { interval:11000;running:true;onTriggered:test.check(false,"Interaction test timed out") }
}
