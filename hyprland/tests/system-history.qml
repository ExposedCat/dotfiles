import QtQuick
import Quickshell

Scope {
    id: test
    property var app: null
    property int step: 0
    property real now: Date.now()
    property real closedAt: 0
    property int closedSamples: 0
    property var hiddenChart: null
    property var liveStats: null
    QtObject {
        id: liveShell
        readonly property bool fixture: false
        readonly property string backend: Quickshell.env("DOTFILES_DESKTOP_BINARY")
        property string panel: ""
        property bool pillHidden: false
    }
    function check(value, message) { if (!value) { console.error("SYSTEM HISTORY FAIL:", message); Qt.exit(1); throw Error(message); } }
    function all(item) { let found=[]; for (const child of item.children || []) { found.push(child); found=found.concat(all(child)); } return found; }
    function named(name) { return all(app.pill.activePane).find(child => child.objectName === name); }
    function seed() {
        app.stats.history = [];
        for (let i=0; i<=60; i++) {
            const cpu = i === 60 ? 23 : Math.round(15 + 60 * Math.exp(-Math.pow((i-20)/5,2)) + 7*Math.abs(Math.sin(i/3)));
            const gpu = i === 60 ? 15 : Math.round(6 + 65 * Math.exp(-Math.pow((i-22)/5,2)) + 5*Math.abs(Math.sin(i/4)));
            app.stats.update(Object.assign({},app.stats.sample,{cpu:cpu,memory:Math.round(40+i*8/60),gpu:gpu,vramUsed:(20+i/3)*1024*1024*1024/100*8,vramTotal:8*1024*1024*1024}), now-60000+i*1000);
        }
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"),"Private fixture required");
        const component=Qt.createComponent("file:"+Quickshell.env("DOTFILES_SHELL_SOURCE")+"/shell.qml");
        check(component.status===Component.Ready,component.errorString());
        app=component.createObject(test); check(!!app,"Shell failed to load");
        check(!!liveShell.backend,"Native sampler required");
        const statsComponent=Qt.createComponent("file:"+Quickshell.env("DOTFILES_SHELL_SOURCE")+"/SystemStats.qml");
        check(statsComponent.status===Component.Ready,statsComponent.errorString());
        liveStats=statsComponent.createObject(test,{shell:liveShell});
        check(!!liveStats,"Live sampler failed to load");
        app.toggle("system");
        advance.start();
    }
    Timer {
        id: advance; interval: 400; repeat: true
        onTriggered: {
            const pane=test.app.pill.activePane, stats=test.app.stats;
            switch(test.step++) {
            case 0:
                test.check(!!pane,"System pane did not open");
                test.check(test.all(pane).filter(c=>c.objectName.startsWith("systemHistory:")).length===4,"Missing resource histories");
                stats.history=[]; stats.sample={};
                test.check(!!test.app.emberTarget,"System lost its live endpoint target");
                test.check(test.named("systemValue:gpu").text==="—","Unavailable GPU was shown as zero");
                test.check(stats.vram===null,"Unavailable VRAM was shown as zero");
                test.check(stats.vramPercent({vramUsed:0,vramTotal:8192})===0,"Unused VRAM was treated as unavailable");
                test.check(stats.vramPercent({vramUsed:2048,vramTotal:8192})===25,"VRAM percentage did not use total capacity");
                test.check(stats.vramPercent({vramUsed:2048,vramTotal:0})===null && stats.vramPercent({vramUsed:2048})===null,"Unknown VRAM capacity produced a percentage");
                const startup=test.named("systemHistory:cpu");
                test.check(startup.segments.length===0 && startup.emberSlot.shapeOpacity===0,"Empty history drew data or a tip");
                stats.update({cpu:null,memory:40,gpu:null},test.now-2000);
                stats.update({cpu:10,memory:40,gpu:0,vramUsed:0,vramTotal:8192},test.now-1000);
                test.check(stats.history[stats.history.length-1].vram===0,"Zero VRAM did not reach the history");
                test.check(startup.timeSpan===0 && startup.segments[0][0].x===startup.inset,"First real sample did not start on the left");
                test.check(startup.emberSlot.x+startup.emberSlot.width/2===startup.inset,"First-sample tip did not start on the left");
                test.check(startup.sampleAt(startup.width-startup.inset)===null,"A single sample was stretched across empty history");
                stats.update({cpu:23,memory:48,gpu:15,vramUsed:2048,vramTotal:8192},test.now);
                test.check(startup.timeSpan===1000 && startup.startTime===test.now-1000,"Startup range did not match the actual collected history");
                const stepWidth=(startup.width-startup.inset*2)/60;
                const oneSecondTip=startup.sampleX(test.now);
                test.check(Math.abs(oneSecondTip-startup.inset-stepWidth)<0.01,"One second of data did not occupy exactly one fixed step");
                test.check(startup.sampleAt(startup.inset).time===test.now-1000 && startup.sampleAt(oneSecondTip).time===test.now,"One-second history inspection did not show 1s ago at the start and Now at the tip");
                test.check(startup.sampleAt(startup.width-startup.inset)===null,"Unused right-hand space showed a sample");
                stats.update({cpu:35,memory:48,gpu:15,vramUsed:4096,vramTotal:8192},test.now+1000);
                test.check(test.named("systemValue:gpu").text==="15%" && stats.vram===50,"GPU headline did not remain load percentage");
                test.check(Math.abs(startup.sampleX(test.now+1000)-startup.inset-stepWidth*2)<0.01,"Two seconds of data did not occupy exactly two fixed steps");
                test.check(startup.sampleX(test.now)===oneSecondTip,"Existing points moved before the chart filled");
                test.check(startup.endTime-startup.sampleAt(startup.inset).time===2000 && startup.sampleAt(startup.sampleX(startup.endTime)).cpu===35,"Two-second history inspection did not show 2s ago at the start and Now at the tip");
                test.seed(); break;
            case 1: {
                const chart=test.named("systemHistory:cpu"), gpu=test.named("systemHistory:gpu"), vram=test.named("systemHistory:vram");
                test.check(chart.segments.length===1 && chart.segments[0].length===61,"History did not retain 60 seconds of real samples");
                test.check(Math.abs(chart.segments[0][0].x-chart.inset)<0.1 && Math.abs(chart.segments[0][60].x-chart.width+chart.inset)<0.1,"History did not place oldest samples on the left and newest samples on the right");
                test.check(Math.abs(chart.emberSlot.x+chart.emberSlot.width/2-chart.width+chart.inset)<0.1,"Live tip is not at the latest sample");
                test.check(chart.width===pane.width,"Chart did not span the full pane");
                test.check(Math.abs(gpu.width-vram.width)<0.1 && Math.abs(gpu.width+vram.width+16-pane.width)<0.1,"GPU charts did not share the row equally");
                test.check(Math.abs(gpu.mapToItem(pane,0,0).y-vram.mapToItem(pane,0,0).y)<0.1 && vram.mapToItem(pane,0,0).x>gpu.mapToItem(pane,0,0).x,"GPU load and VRAM are not side by side");
                test.check(vram.segments.length===1 && vram.segments[0].length===61 && Math.abs(stats.vram-40)<0.01,"VRAM capacity history was not retained");
                test.check(Math.abs(vram.sampleAt(vram.width-vram.inset).vram-40)<0.01,"VRAM inspection returned the wrong percentage");
                const gpuRow=test.named("systemMetric:gpu"), network=test.named("systemNetwork");
                test.check(network.y-(gpuRow.y+gpuRow.height)>=24,"Network section did not receive extra spacing");
                vram.forceActiveFocus(); test.check(pane.metric==="vram" && test.app.emberTarget===vram.emberSlot,"VRAM focus did not select its live tip");
                test.named("systemMetric:cpu").forceActiveFocus();
                test.check(chart.sampleY(100)===chart.inset && chart.sampleY(0)===chart.height-chart.inset,"Usage scale is not fixed at 0–100%");
                test.check(chart.sampleAt(chart.width-chart.inset).cpu===23,"History inspection did not return the latest sample on the right");
                test.check(chart.sampleAt(chart.inset).time===test.now-60000,"History inspection did not return the oldest sample on the left");
                chart.moveInspection(-1); test.check(chart.inspected.cpu===23,"Keyboard inspection did not start at the latest sample");
                chart.moveInspection(-1); test.check(chart.inspected.time===test.now-1000,"Left arrow did not inspect the older sample to the left");
                chart.moveInspection(1); test.check(chart.inspected.time===test.now,"Right arrow did not inspect the newer sample to the right"); chart.inspectionIndex=-1;
                const previousX=chart.sampleX(test.now-10000);
                stats.update(Object.assign({},stats.sample),test.now+1000);
                test.check(chart.timeSpan===60000,"Full history did not stay capped at 60 seconds");
                test.check(Math.abs(previousX-chart.sampleX(test.now-10000)-(chart.width-chart.inset*2)/60)<0.01,"Full history did not shift older samples left by one step");
                test.check(Math.abs(chart.sampleX(stats.sampleTime)-chart.width+chart.inset)<0.01,"New samples did not stay at the right edge after the chart filled");
                test.check(test.named("systemIcon:cpu").height===test.named("systemHeader:cpu").height,"Icon does not span name and details");
                for (const child of test.all(pane).filter(c=>c.font && typeof c.text==="string")) {
                    test.check(child.font.family===pane.theme.fontFamily,"Text did not use the shared font");
                    test.check(child.font.pixelSize===(child.objectName.startsWith("systemValue:") ? pane.theme.bodySize+6 : pane.theme.bodySize),"Text did not use the unified sizes: "+child.text);
                }
                test.check(pane.implicitHeight<=pane.height,"System content overflows the popup");
                test.check(Math.abs(pane.height-pane.implicitHeight)<1,"System popup retained unused fixed height");
                const footer=test.named("systemFooter");
                test.check(Math.abs(pane.height-footer.y-footer.height)<1,"Empty space remains below the system footer");
                stats.history=[{time:test.now-5000,cpu:10,gpu:0},{time:test.now-4000,cpu:null,gpu:0},{time:test.now-3000,cpu:25,gpu:null},{time:test.now,cpu:50,gpu:null}];
                test.check(chart.segments.length===3,"Null samples or collection gaps were joined by a line");
                test.check(gpu.segments.length===1 && gpu.segments[0].length===2,"Zero or unavailable GPU samples were drawn incorrectly");
                stats.update(Object.assign({},stats.sample,{cpu:0}),test.now+61000);
                test.check(stats.history.length===1,"Expired history survived a long close/reopen gap");
                test.check(chart.sampleAt(chart.width-chart.inset)===null,"Empty history was backfilled");
                stats.history=[]; stats.fixtureUpdate(); test.closedAt=stats.sampleTime;
                test.hiddenChart=chart;
                test.app.panel=""; break;
            }
            case 2:
                test.check(!stats.active,"Closed popup still marked visible");
                test.check(!test.hiddenChart.active && test.hiddenChart.segments.length===0,"Closed chart kept building render geometry");
                if (stats.sampleTime < test.closedAt+1500) { test.step--; break; }
                test.check(stats.history.length>=3,"History stopped accumulating while closed");
                test.check(!test.liveStats.active && test.liveStats.history.length>=3 && !test.liveStats.error,"Native sampler stopped while closed");
                test.closedSamples=stats.history.length;
                test.app.toggle("system"); break;
            case 3:
                test.check(stats.active,"Reopened popup not marked visible");
                test.check(stats.history.length>=test.closedSamples,"Reopening discarded background samples");
                test.check(test.named("systemHistory:cpu").segments[0].length>=test.closedSamples,"Reopened chart did not immediately show background history");
                console.warn("SYSTEM HISTORY PASS: split GPU load/VRAM, capacity scaling, GPU load headline, network spacing, fixed steps, rolling history, inspection, gaps, unified typography, panel fit, continuous native sampling, hidden rendering paused, background history on reopen");
                advance.stop();
                if (!Quickshell.env("DOTFILES_STATS_PREVIEW")) Qt.quit();
                break;
            }
        }
    }
    Timer { interval: 12000; running: !Quickshell.env("DOTFILES_STATS_PREVIEW"); onTriggered: test.check(false,"History check timed out") }
}
