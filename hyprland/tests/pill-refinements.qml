import QtQuick
import Quickshell

Scope {
    id: test
    property var app: null
    property var group: null
    property var card: null
    property var accept: null
    property var later: null
    property var previousTarget: null
    property real baseHeight: 0
    property int step: 0
    property int redirects: 0
    function check(value, message) { if (!value) { console.error("REFINEMENT FAIL:", message); Qt.exit(1); throw Error(message); } }
    function all(item) { let found=[]; for(const c of item.children||[]) {found.push(c);found=found.concat(all(c));}return found; }
    function entry(i) { return {id:"refine-"+i,app:"Messages",summary:i<3?"Conversation":"Message "+i,body:"A message with actions",time:Date.now()-i,read:false,critical:false}; }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"),"Private fixture required");
        const c=Qt.createComponent("file:"+Quickshell.env("DOTFILES_SHELL_SOURCE")+"/shell.qml");
        check(c.status===Component.Ready,c.errorString()); app=c.createObject(test);
        app.pill.hoverExpanded=true; advance.start();
    }
    Timer {
        id:advance; interval:600; repeat:true
        onTriggered: {
            switch(test.step++) {
            case 0:
                test.app.toggle("system"); test.app.stats.sample={};
                test.check(!!test.app.emberTarget,"System waited for a statistics sample before choosing its target");
                test.check(!test.all(test.app.pill.activePane).some(c=>typeof c.getContext==="function"),"The ambiguous history chart is still present"); break;
            case 1:
                test.check(test.app.emberTarget.width===82 && test.app.emberTarget.height===38,"System did not use the metric value capsule");
                test.app.toggle("ethernet"); break;
            case 2:
                test.previousTarget=test.app.emberTarget;
                test.all(test.app.pill.activePane).find(c=>c.objectName==="network-download").forceActiveFocus();
                test.check(test.app.emberTarget===test.previousTarget,"A speed value stole the bead");
                test.app.notifications.entries=[test.entry(0),test.entry(1),test.entry(2)];
                const live={}; for(const e of test.app.notifications.entries) live[e.id]={actions:[{identifier:"accept",text:"Accept",invoke:()=>{}},{identifier:"later",text:"Later",invoke:()=>{}}],hasInlineReply:false};
                test.app.notifications.live=live; test.app.toggle("notifications"); break;
            case 3:
                test.group=test.all(test.app.pill.activePane).find(c=>c.group && c.group.entries.length===3);
                test.check(!!test.group,"Grouped messages were not created"); test.card=test.group.firstCard;
                test.check(!test.group.expanded && test.group.stackCount===2, "Center must preserve collapsed app/title groups");
                test.app.pill.activePane.toggleGroup(test.group.group.key);
                test.baseHeight=test.card.implicitHeight; break;
            case 4: {
                const reveal=test.all(test.card).find(c=>c.objectName==="notificationActionReveal");
                test.check(reveal.reveal===1 && test.card.detailsExpanded && test.group.unfold===1,"Notification actions are not visible on opening: " + JSON.stringify({base:test.baseHeight,height:test.card.implicitHeight,reveal:reveal.reveal,expanded:test.card.actionsExpanded,focus:test.card.containsFocus,actions:test.card.hasActions}));
                test.accept=test.all(test.card).find(c=>c.text==="Accept" && c.emberSlot);
                test.later=test.all(test.card).find(c=>c.text==="Later" && c.emberSlot);
                test.accept.forceActiveFocus(); break;
            }
            case 5:
                test.check(test.app.emberTarget===test.accept.emberSlot && test.app.pill.ember.dock===test.accept.emberSlot,"Notification action did not receive the fill");
                advance.stop(); fast.start(); break;
            case 6:
                test.check(test.redirects===6 && test.app.pill.ember.dock===test.app.emberTarget,"Rapid retargeting did not settle on the latest action");
                test.card.hoveredAction=null; test.previousTarget=test.app.emberTarget; test.app.pill.contentItem.forceActiveFocus(); break;
            case 7:
                test.check(test.app.emberTarget===test.previousTarget,"A gap sent the marker back to the first card");
                test.all(test.app.pill.activePane).filter(c=>c.text==="Later" && c.emberSlot)[1].forceActiveFocus(); break;
            case 8:
                test.check(test.app.emberTarget!==test.previousTarget,"A new notification target did not receive the marker");
                test.check(test.all(test.card).find(c=>c.objectName==="notificationBody").maximumLineCount===5,"Expanded body is not capped at five lines");
                test.app.panel=""; test.app.pill.hoverExpanded=false;
                test.app.notifications.popups=[]; test.app.notifications.queuedPopups=[];
                test.app.notifications.showPopup(test.entry(0));
                test.check(test.app.notifications.popups.length===0,"A notification already seen in the center returned as a banner");
                test.app.notifications.showPopup(test.entry(20)); break;
            case 9:
                test.check(test.app.pill.pillState==="compact","A notification expanded the center pill");
                test.check(test.app.overlays.bannerWindow.visible && test.app.overlays.banners.presentationCount===1,"Corner notification surface did not present the banner");
                test.app.notifications.showPopup(test.entry(21)); break;
            case 10:
                test.check(test.app.overlays.banners.presentationCount===2 && test.app.overlays.banners.inputRegions.length===2,"Corner banners did not stack independently");
                console.warn("REFINEMENT PASS: immediate system target, readable meters, fixed network target, action reveal/fill, continuous rapid redirects, expandable groups, five-line bodies, retained gap target, independent corner banners"); Qt.quit();
            }
        }
    }
    Timer {
        id:fast; interval:50; repeat:true
        onTriggered: {
            const ember=test.app.pill.ember, shape=test.all(test.app.pill.contentItem).find(c=>c.objectName==="emberShape");
            const before=shape.mapToItem(test.app.pill.contentItem,shape.width/2,shape.height/2);
            test.card.hoveredAction=test.redirects%2===0?test.later:test.accept;
            const after=shape.mapToItem(test.app.pill.contentItem,shape.width/2,shape.height/2);
            test.check(Math.hypot(before.x-after.x,before.y-after.y)<0.1,"A rapid redirect teleported the bead");
            if(test.redirects>0) test.check(ember.redirecting && ember.takeoffEnd<=0.06,"A redirect restarted the slow takeoff");
            if(++test.redirects===6) { stop(); settle.start(); }
        }
    }
    Timer { id:settle; interval:400; onTriggered:advance.start() }
    Timer { interval:15000; running:true; onTriggered:test.check(false,"Refinement check timed out") }
}
