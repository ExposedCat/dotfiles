import QtQuick
import Quickshell

// Reorders, reflows, and inline replies must never overlap neighboring cards.
Scope {
    id: test
    property var app: null
    property int step: 0
    property var originals: ({})
    function check(v,m) { if(!v) { console.error("LAYOUT FAIL:",m);Qt.exit(1);throw Error(m); } }
    function all(item) { let a=[];for(const c of item.children||[]) {a.push(c);a=a.concat(all(c));}return a; }
    function cards() { return all(app.pill.activePane).filter(c=>c.entry&&c.inCenter!==undefined).sort((a,b)=>a.y-b.y); }
    function separated() {
        const items=cards();check(items.length===2,"Two cards required");
        check(items[1].y>=items[0].y+items[0].height+9.5,"Reflow/reordering overlapped the cards");
        for(const c of items) if(originals[c.entry.id]) check(originals[c.entry.id]===c,"Reordering recreated a card");
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"),"Private fixture required");
        const c=Qt.createComponent("file:"+Quickshell.env("DOTFILES_SHELL_SOURCE")+"/shell.qml");check(c.status===Component.Ready,c.errorString());app=c.createObject(test);
        app.notifications.entries=[{id:"short",app:"Messages",summary:"Short",body:"One line",time:Date.now(),read:false},{id:"long",app:"Messages",summary:"Long",body:"A message long enough to wrap over several lines. ".repeat(8),time:Date.now()-1,read:false}];
        const live={};for(const e of app.notifications.entries) live[e.id]={actions:[{identifier:"read",text:"Mark as read",invoke:()=>{}}],hasInlineReply:true,expire:()=>{},dismiss:()=>{}};app.notifications.live=live;app.toggle("notifications");app.pill.activePane.toggleGroup("messages");
    }
    Timer {
        interval:350;repeat:true;running:!!test.app
        onTriggered:{
            switch(test.step++) {
            case 0:
                test.separated();for(const c of test.cards())test.originals[c.entry.id]=c;
                test.app.notifications.entries=test.app.notifications.entries.slice().reverse();break;
            case 1:
                test.separated();test.app.pill.paneWidth=900;break;
            case 2:
                test.separated();test.app.notifications.entries=test.app.notifications.entries.map(e=>e.id==="short"?Object.assign({},e,{body:"The short message has become longer. ".repeat(9)}):e);break;
            case 3:
                test.separated();test.app.notifications.startReply("long","center");break;
            case 4:
                test.separated();test.app.notifications.cancelReply("long");test.app.notifications.entries=test.app.notifications.entries.slice().reverse();break;
            case 5:
                test.separated();test.app.pill.paneWidth=1080;break;
            case 6:
                test.separated();test.app.pill.activePane.toggleGroup("messages");break;
            case 7: {
                const group=test.all(test.app.pill.activePane).find(c=>c.group&&c.group.entries);
                test.check(!group.expanded && group.unfold===0 && Math.abs(group.height-group.collapsedHeight)<1,"Group did not collapse to its stack preview");
                test.check(group.firstCard.detailsExpanded,"Collapsing the group collapsed the visible message body");
                test.app.pill.activePane.toggleGroup("messages");break;
            }
            case 8:
                test.separated();test.check(test.cards().every(c=>c.opacity===1&&c.enabled),"Opening the group did not restore its messages");
                console.warn("LAYOUT PASS: reorder, variable heights, width reflow, reply/cancel, stable delegates, grouped collapse/expand");Qt.quit();
            }
        }
    }
    Timer { interval:5000;running:true;onTriggered:test.check(false,"Timed out") }
}
