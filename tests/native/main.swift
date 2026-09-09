import AppKit
import PDFKit

func check(_ value:@autoclosure ()->Bool,_ message:String) throws {if !value(){throw BranchError("FAIL: "+message)}}
func near(_ a:CGFloat,_ b:CGFloat)->Bool{abs(a-b)<0.00001}
let app=NSApplication.shared
let temp=FileManager.default.temporaryDirectory.appendingPathComponent("branch-native-test-"+UUID().uuidString)
try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:temp)}
do {
    for direction in ["horizontal","compact","vertical"] {
        var d=MindDocument.create("中文主节点",sample:true);d.raw["layout"]=direction
        let root=d.root.id,branch=d.children(root)[0].id,leaf=d.children(branch)[0].id
        d.set(leaf,"position",["x":650,"y":420]);let before=MindLayout.calculate(d)
        d.translate(root,by:CGPoint(x:120,y:-70),origin:before[0].rect.origin)
        let after=MindLayout.calculate(d)
        for (a,b) in zip(before,after){try check(near(b.rect.minX,a.rect.minX+120)&&near(b.rect.minY,a.rect.minY-70),"whole tree translation \(direction)")}
        d.set(branch,"collapsed",true);let hidden=d.node(leaf)!.position!;d.translate(root,by:CGPoint(x:10,y:20),origin:after[0].rect.origin);try check(d.node(leaf)!.position! == CGPoint(x:hidden.x+10,y:hidden.y+20),"hidden manual descendants")
        d.set(branch,"collapsed",false)
        do{try d.move(branch,to:leaf);throw BranchError("cycle accepted")}catch let error as BranchError{try check(error.message != "cycle accepted","cycle rejection")}
        let oldCount=d.nodes.count;try d.remove(branch);try check(d.nodes.count==oldCount-2,"subtree deletion")
        let md=Exchange.markdown(d),round=try Exchange.fromMarkdown(md);try check(Exchange.markdown(round)==md,"Markdown round trip")
        let opml=try Exchange.fromOPML(Exchange.opml(d));try check(Exchange.markdown(opml)==md,"OPML round trip")
    }
    for direction in ["horizontal","compact","vertical"] {
        var forest=MindDocument.create("First Tree",sample:true);forest.raw["layout"]=direction
        let first=forest.root.id,before=MindLayout.calculate(forest),snapshot=forest
        let second=forest.addRoot(title:"Second Tree",at:CGPoint(x:-360,y:280)),child=forest.add(second,title:"Second Child")
        try DocumentStore.validate(forest)
        try check(forest.roots.count==2 && snapshot.roots.count==1 && number(forest.raw["version"])==2,"forest create and undo snapshot")
        let by=Dictionary(uniqueKeysWithValues:MindLayout.calculate(forest).map{($0.id,$0)})
        for p in before{try check(by[p.id]!.rect==p.rect,"new root preserves existing tree positions")}
        try check(by[second]!.rect.origin==CGPoint(x:-360,y:280),"root uses clicked canvas position")
        forest.translate(second,by:CGPoint(x:90,y:-45),origin:by[second]!.rect.origin)
        let shifted=Dictionary(uniqueKeysWithValues:MindLayout.calculate(forest).map{($0.id,$0)})
        for (id,p) in by {let delta=forest.descendants(second).contains(id) ? CGPoint(x:90,y:-45):.zero;try check(near(shifted[id]!.rect.minX,p.rect.minX+delta.x)&&near(shifted[id]!.rect.minY,p.rect.minY+delta.y),"independent tree translation")}
        try check(MindLayout.calculate(forest,focus:second).count==2,"focus one tree")
        let md=Exchange.markdown(forest),mdRound=try Exchange.fromMarkdown(md),opmlRound=try Exchange.fromOPML(Exchange.opml(forest))
        try check(mdRound.roots.count==2 && Exchange.markdown(mdRound)==md,"forest Markdown round trip")
        try check(opmlRound.roots.count==2 && Exchange.markdown(opmlRound)==md,"forest OPML round trip")
        forest.connections=[["from":child,"to":first,"title":"cross tree"]]
        let canvas=MindCanvas(frame:CGRect(x:0,y:0,width:1000,height:800));canvas.reload(forest,selection:second,focus:second)
        let pdf=PDFDocument(data:try canvas.exportData(pdf:true))?.string ?? ""
        try check(pdf.contains("First Tree")&&pdf.contains("Second Tree"),"full export includes every tree even while focused")
        let storage=DocumentStore(root:temp.appendingPathComponent(direction));forest=try storage.save(forest,expected:0)
        let reread=try storage.read(forest.id);try check(reread.roots.count==2 && reread.nodes.count==forest.nodes.count,"native forest save/reopen")
        try forest.remove(second);try check(forest.roots.count==1 && forest.node(child)==nil && forest.connections.isEmpty,"delete tree and connections")
        do{try forest.remove(first);throw BranchError("last root deleted")}catch let e as BranchError{try check(e.message != "last root deleted","last root protected")}
        var cycle=reread;cycle.set(child,"parent",child)
        do{try DocumentStore.validate(cycle);throw BranchError("forest cycle accepted")}catch let e as BranchError{try check(e.message != "forest cycle accepted","forest cycle rejection")}
    }
    print("PASS: multiple roots, independent movement, focus, full PDF, Markdown/OPML, save/reopen, delete and last-root guard")
    let root=temp.appendingPathComponent("store");let store=DocumentStore(root:root)
    var d=MindDocument.create("原生互通",sample:true);d.raw["customMetadata"]=["keep":true];d.set(d.root.id,"customNodeField","保留")
    d=try store.save(d,expected:0);try check(d.revision==1,"initial save")
    let script="import sys;sys.path.insert(0,sys.argv[1]);import store;d=store.read(sys.argv[2]);d['nodes'][0]['title']='MCP 修改';store.save(d,d['revision'])"
    let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/python3");p.arguments=["-c",script,FileManager.default.currentDirectoryPath+"/scripts",d.id];p.environment=ProcessInfo.processInfo.environment.merging(["BRANCH_HOME":root.path,"PYTHONDONTWRITEBYTECODE":"1"]){_,b in b};try p.run();p.waitUntilExit();try check(p.terminationStatus==0,"Python store write")
    let external=try store.read(d.id);try check(external.root.title=="MCP 修改"&&external.revision==2,"native reads MCP")
    do{_ = try store.save(d,expected:1);throw BranchError("conflict accepted")}catch let e as BranchError{try check(e.message.contains("版本冲突"),"revision conflict")}
    var updated=external;updated.title="原生再次保存";updated=try store.save(updated,expected:2);try check(updated.raw["customMetadata"] != nil && updated.root.text("customNodeField")=="保留","unknown fields retained")
    try Data("corrupt".utf8).write(to:store.path(d.id));let recovered=try store.read(d.id);try check(recovered.revision==2 && recovered.raw["_recovered"] as? Bool==true,"backup recovery")
    let input=URL(fileURLWithPath:"tests/fixtures/transparent.png"),jpeg=temp.appendingPathComponent("converted.jpg");try jpegFile(input,jpeg);let jpg=try Data(contentsOf:jpeg);try check(jpg.starts(with:[255,216,255]),"PNG actually converted to JPEG")
    var drawing=MindDocument.create("Native PDF Search 中文",sample:true);drawing.set(drawing.nodes.last!.id,"image","data:image/jpeg;base64,"+jpg.base64EncodedString());drawing.connections=[["from":drawing.nodes[1].id,"to":drawing.nodes[2].id,"title":"关系标题"]]
    let canvas=MindCanvas(frame:CGRect(x:0,y:0,width:1200,height:800));canvas.reload(drawing,selection:drawing.root.id,focus:nil)
    let pdf=try canvas.exportData(pdf:true);try check(PDFDocument(data:pdf)?.string?.contains("Native PDF Search")==true,"PDF searchable native text")
    let raster=try canvas.exportData(pdf:false);try check(NSImage(data:raster) != nil && raster.starts(with:[255,216,255]),"JPG export")
    let snapshot=drawing;drawing.set(drawing.root.id,"title","改变");try check(snapshot.root.title=="Native PDF Search 中文","undo snapshot value semantics")
    var large=MindDocument.create("500 节点");for i in 1..<500{large.add(large.root.id,title:"节点 \(i) 中文内容")}
    let start=Date();let layout=MindLayout.calculate(large);let elapsed=Date().timeIntervalSince(start)*1000;try check(layout.count==500,"500 nodes layout");for p in layout{try check(p.rect.minX.isFinite&&p.rect.minY.isFinite,"finite coordinates")}
    print(String(format:"PASS: native layout/translation/collapse, undo values, Markdown/OPML, native-Python storage/conflict/recovery, JPG, searchable PDF; 500-node layout %.1f ms",elapsed))
} catch {fputs(error.localizedDescription+"\n",stderr);exit(1)}
