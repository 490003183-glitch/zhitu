import AppKit
import ImageIO

final class ImageCache {
    private let cache=NSCache<NSString,NSImage>()
    init(){cache.totalCostLimit=48*1024*1024;cache.countLimit=100}
    func image(_ value:String) -> NSImage? {
        guard !value.isEmpty else{return nil}
        let key=value as NSString;if let image=cache.object(forKey:key){return image}
        guard let comma=value.firstIndex(of:","),let data=Data(base64Encoded:String(value[value.index(after:comma)...])),let src=CGImageSourceCreateWithData(data as CFData,nil),let cg=CGImageSourceCreateThumbnailAtIndex(src,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1000,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else{return nil}
        let image=NSImage(cgImage:cg,size:CGSize(width:cg.width,height:cg.height));cache.setObject(image,forKey:key,cost:cg.width*cg.height*4);return image
    }
}
final class NodeAX: NSAccessibilityElement {
    var activate:(()->Void)?
    override func accessibilityPerformPress() -> Bool {activate?();return true}
}
final class CanvasEditor:NSTextView {
    var finish:((Bool)->Void)?
    override func keyDown(with event:NSEvent) {
        if !hasMarkedText(),event.keyCode==53 {finish?(false);return}
        if !hasMarkedText(),event.keyCode==36,!event.modifierFlags.contains(.shift) {finish?(true);return}
        super.keyDown(with:event)
    }
}
final class MindCanvas:NSView {
    weak var controller:BranchController?
    var document=MindDocument.create()
    var placements=[NodePlacement](),nodeMap=[String:MindNode]()
    var parents=Set<String>()
    var selected="",focus:String?,search="",connectFrom:String?
    var selectedIDs=Set<String>()
    var marquee:CGRect?
    var spaceHeld=false,spaceUsed=false
    var zoom:CGFloat=1,offset=CGPoint(x:80,y:100)
    var editor:CanvasEditor?,editingID:String?
    let images=ImageCache()
    enum DragMode {case nodes,marquee,pan}
    struct Drag {var id:String?;var start:CGPoint;var offset:CGPoint;var original:[NodePlacement];var ids:Set<String>;var manual:Bool;var moved=false;var target:String?;var mode:DragMode = .nodes;var selection=Set<String>();var baseSelection=Set<String>()}
    var drag:Drag?
    override var isFlipped:Bool{true}
    override var acceptsFirstResponder:Bool{true}
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool{true}
    override init(frame:NSRect){super.init(frame:frame);registerForDraggedTypes([.fileURL]);setAccessibilityRole(.group);setAccessibilityLabel("思维导图画布")}
    required init?(coder:NSCoder){fatalError()}
    func reload(_ d:MindDocument,selection:String,focus:String?){
        let reset=document.id != d.id || selected != selection || self.focus != focus
        document=d;selected=selection;self.focus=focus;nodeMap=Dictionary(uniqueKeysWithValues:d.nodes.map{($0.id,$0)});parents=Set(d.nodes.compactMap(\.parent));placements=MindLayout.calculate(d,focus:focus)
        selectedIDs=reset ? [selection]:selectedIDs.intersection(placements.map(\.id));needsDisplay=true;refreshAX()
    }
    override func setFrameSize(_ newSize:NSSize){let old=frame.size;super.setFrameSize(newSize);if old.width>0{offset.x+=(newSize.width-old.width)/2;offset.y+=(newSize.height-old.height)/2};needsDisplay=true;refreshAX()}
    func mapPoint(_ p:CGPoint) -> CGPoint{CGPoint(x:(p.x-offset.x)/zoom,y:(p.y-offset.y)/zoom)}
    func contentBounds() -> CGRect {placements.reduce(CGRect.null){$0.union($1.rect)}.insetBy(dx:-60,dy:-100)}
    func fit(){guard !placements.isEmpty else{return};let b=contentBounds();zoom=max(0.08,min(1.2,(bounds.width-70)/b.width,(bounds.height-50)/b.height));offset=CGPoint(x:(bounds.width-b.width*zoom)/2-b.minX*zoom,y:(bounds.height-b.height*zoom)/2-b.minY*zoom-12);needsDisplay=true;refreshAX();controller?.updateFooter()}
    func scale(_ factor:CGFloat,at point:CGPoint?=nil){let p=point ?? CGPoint(x:bounds.midX,y:bounds.midY),old=zoom;zoom=max(0.08,min(3,zoom*factor));offset=CGPoint(x:p.x-(p.x-offset.x)*zoom/old,y:p.y-(p.y-offset.y)*zoom/old);needsDisplay=true;refreshAX();controller?.updateFooter()}
    func hit(_ point:CGPoint)->NodePlacement?{placements.reversed().first{$0.rect.insetBy(dx:-6,dy:-6).contains(point)}}
    func select(_ id:String){setSelection([id],primary:id)}
    func setSelection(_ ids:Set<String>,primary:String?=nil){
        let ids=ids.intersection(placements.map(\.id))
        let next=primary.flatMap{ids.contains($0) ? $0:nil} ?? (ids.contains(selected) ? selected:placements.first{ids.contains($0.id)}?.id)
        if let next {selected=next;controller?.select(next)}
        selectedIDs=ids;needsDisplay=true;refreshAX();controller?.updateFooter();if controller?.showInspector==true{controller?.buildInspector()}
    }
    static func selectionRect(from a:CGPoint,to b:CGPoint)->CGRect{CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))}
    func portY(_ p:NodePlacement)->CGFloat{p.depth>0 && ["","line"].contains(nodeMap[p.id]?.text("shape") ?? "") ? p.rect.maxY:p.rect.midY}
    func branchPath(_ a:NodePlacement,_ b:NodePlacement)->NSBezierPath{
        let vertical=document.layout=="vertical",path=NSBezierPath()
        let start=vertical ? CGPoint(x:a.rect.midX,y:a.rect.maxY):CGPoint(x:a.rect.maxX,y:portY(a)),end=vertical ? CGPoint(x:b.rect.midX,y:b.rect.minY):CGPoint(x:b.rect.minX,y:portY(b))
        path.move(to:start)
        if nodeMap[b.id]?.text("lineStyle")=="straight" {path.line(to:end)} else {
            let cp1=vertical ? CGPoint(x:start.x,y:(start.y+end.y)/2):CGPoint(x:start.x+(end.x-start.x)*0.55,y:start.y)
            let cp2=vertical ? CGPoint(x:end.x,y:(start.y+end.y)/2):CGPoint(x:end.x-(end.x-start.x)*0.55,y:end.y)
            path.curve(to:end,controlPoint1:cp1,controlPoint2:cp2)
        }
        return path
    }
    func relationPath(_ a:NodePlacement,_ b:NodePlacement)->NSBezierPath{
        let p=NSBezierPath(),start=CGPoint(x:a.rect.midX,y:a.rect.minY),end=CGPoint(x:b.rect.midX,y:b.rect.minY),q=CGPoint(x:(a.rect.minX+b.rect.minX)/2,y:min(a.rect.minY,b.rect.minY)-70)
        p.move(to:start);p.curve(to:end,controlPoint1:CGPoint(x:start.x+(q.x-start.x)*2/3,y:start.y+(q.y-start.y)*2/3),controlPoint2:CGPoint(x:end.x+(q.x-end.x)*2/3,y:end.y+(q.y-end.y)*2/3));return p
    }
    override func draw(_ dirtyRect:NSRect){
        (document.theme=="light" ? NSColor.white:NSColor(hex:"#111112")).setFill();bounds.fill()
        NSGraphicsContext.saveGraphicsState();let t=NSAffineTransform();t.translateX(by:offset.x,yBy:offset.y);t.scale(by:zoom);t.concat();drawScene(decorations:true);NSGraphicsContext.restoreGraphicsState()
        if let marquee {let path=NSBezierPath(rect:marquee);NSColor.controlAccentColor.withAlphaComponent(0.12).setFill();path.fill();NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke();path.lineWidth=1;path.stroke()}
    }
    func drawScene(decorations:Bool){
        let by=Dictionary(uniqueKeysWithValues:placements.map{($0.id,$0)}),light=document.theme=="light"
        for b in placements {guard let parent=b.parent,let a=by[parent] else{continue};let p=branchPath(a,b);NSColor(hex:b.color).setStroke();p.lineWidth=1.5;p.lineCapStyle = .round;if nodeMap[b.id]?.text("lineStyle")=="dashed"{p.setLineDash([5,5],count:2,phase:0)};p.stroke()}
        for c in document.connections {
            guard let a=by[c["from"] as? String ?? ""],let b=by[c["to"] as? String ?? ""] else{continue}
            let path=relationPath(a,b);NSColor(hex:"#9998aa").setStroke();path.lineWidth=1.5;path.setLineDash([5,5],count:2,phase:0);path.stroke()
            if let title=c["title"] as? String,!title.isEmpty {(title as NSString).draw(at:CGPoint(x:(a.rect.minX+b.rect.minX)/2+a.rect.width/2,y:min(a.rect.minY,b.rect.minY)-44),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.secondaryLabelColor])}
        }
        for p in placements {
            guard let n=nodeMap[p.id] else{continue}
            NSGraphicsContext.saveGraphicsState()
            if decorations,!search.isEmpty,!(n.title+" "+n.text("tags")).localizedCaseInsensitiveContains(search){NSGraphicsContext.current?.cgContext.setAlpha(0.22)}
            let rect=p.rect,color=NSColor(hex:p.color),shape=n.text("shape")
            if p.depth==0 || !["","line"].contains(shape) {
                let path=NSBezierPath(roundedRect:rect,xRadius:shape=="rectangle" ? 0:shape=="pill" ? rect.height/2:10,yRadius:shape=="rectangle" ? 0:shape=="pill" ? rect.height/2:10)
                (light ? NSColor(hex:"#f1f1f3"):NSColor(hex:"#29292c")).setFill();path.fill();if p.depth>0{color.setStroke();path.lineWidth=1;path.stroke()}
            } else {let line=NSBezierPath();line.move(to:CGPoint(x:rect.minX,y:rect.maxY));line.line(to:CGPoint(x:rect.maxX,y:rect.maxY));color.setStroke();line.lineWidth=1.5;line.stroke()}
            let textColor=n.flag("done") ? NSColor.secondaryLabelColor:light ? NSColor(hex:"#343436"):NSColor(hex:"#e4e4e6")
            var attributes:[NSAttributedString.Key:Any]=[.font:p.font,.foregroundColor:textColor]
            if n.flag("done"){attributes[.strikethroughStyle]=NSUnderlineStyle.single.rawValue}
            for (i,line) in p.lines.enumerated(){(line as NSString).draw(at:CGPoint(x:rect.minX+12,y:rect.minY+(p.depth==0 ? 9:5)+CGFloat(i)*(n.fontSize+6)),withAttributes:attributes)}
            if let image=images.image(n.text("image")) {
                let target=CGRect(x:rect.minX+10,y:rect.minY+CGFloat(p.lines.count)*(n.fontSize+6)+10,width:rect.width-20,height:n.imageHeight),ratio=min(target.width/image.size.width,target.height/image.size.height),size=CGSize(width:image.size.width*ratio,height:image.size.height*ratio)
                image.draw(in:CGRect(x:target.midX-size.width/2,y:target.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            }
            if n.flag("task"){(n.flag("done") ? "☑":"☐" as NSString).draw(at:CGPoint(x:rect.maxX-16,y:rect.minY-20),withAttributes:[.font:NSFont.systemFont(ofSize:15),.foregroundColor:color])}
            let info=[n.text("notes").isEmpty ? "":"≡",n.text("tags").isEmpty ? "":"# "+n.text("tags"),n.text("link").isEmpty ? "":"↗"].filter{!$0.isEmpty}.joined(separator:"  ")
            (info as NSString).draw(at:CGPoint(x:rect.minX+3,y:rect.minY-18),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.secondaryLabelColor])
            if decorations {
                if selectedIDs.contains(p.id) || drag?.target==p.id {color.setStroke();let selection=NSBezierPath(roundedRect:rect.insetBy(dx:-4,dy:-4),xRadius:6,yRadius:6);selection.lineWidth=drag?.target==p.id ? 3:1.5;selection.stroke()}
                if parents.contains(p.id),(selectedIDs.contains(p.id) || n.flag("collapsed")) {let r=CGRect(x:rect.maxX+4,y:portY(p)-8,width:16,height:16);(light ? NSColor.white:NSColor(hex:"#292b30")).setFill();let circle=NSBezierPath(ovalIn:r);circle.fill();color.setStroke();circle.lineWidth=0.8;circle.stroke();(n.flag("collapsed") ? "+":"−" as NSString).draw(at:CGPoint(x:r.minX+3,y:r.minY),withAttributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:color])}
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    func refreshAX(){
        guard let window else{return}
        let elements=placements.map {p -> NodeAX in
            let a=NodeAX();a.setAccessibilityRole(.button);a.setAccessibilityEnabled(true);a.setAccessibilityLabel(nodeMap[p.id]?.title ?? "节点");a.setAccessibilityParent(self)
            a.setAccessibilityValue(selectedIDs.contains(p.id) ? "已选中":"未选中")
            let r=CGRect(x:offset.x+p.rect.minX*zoom,y:offset.y+p.rect.minY*zoom,width:p.rect.width*zoom,height:p.rect.height*zoom)
            a.setAccessibilityFrame(window.convertToScreen(convert(r,to:nil)));a.activate={[weak self] in guard let self else{return};self.window?.makeFirstResponder(self);self.select(p.id)};return a
        }
        setAccessibilityChildren((elements as [Any]) + (editor.map {[$0] as [Any]} ?? []))
    }
    func edit(_ id:String){
        commitEditor();guard let p=placements.first(where:{$0.id==id}),let n=nodeMap[id] else{return};select(id)
        let r=CGRect(x:offset.x+p.rect.minX*zoom,y:offset.y+p.rect.minY*zoom,width:max(170,p.rect.width*zoom),height:max(50,p.rect.height*zoom))
        let text=CanvasEditor(frame:r);text.string=n.title;text.font=n.font.withSize(max(12,n.fontSize*zoom));text.isRichText=false;text.isAutomaticQuoteSubstitutionEnabled=false;text.backgroundColor=document.theme=="light" ? .white:NSColor(hex:"#323235");text.textColor = .labelColor;text.textContainerInset=CGSize(width:9,height:7);text.isVerticallyResizable=true;text.autoresizingMask=[];text.allowsUndo=true
        text.setAccessibilityLabel("编辑节点标题");text.finish={[weak self] commit in self?.commitEditor(commit)};addSubview(text);editor=text;editingID=id;window?.makeFirstResponder(text);text.selectAll(nil);refreshAX()
    }
    func commitEditor(_ commit:Bool=true){guard let editor,let id=editingID else{return};let value=editor.string;self.editor=nil;editingID=nil;editor.removeFromSuperview();window?.makeFirstResponder(self);if commit,value != nodeMap[id]?.title{controller?.editNode(id,key:"title",value:value)};refreshAX()}
    override func mouseDown(with event:NSEvent){
        commitEditor();window?.makeFirstResponder(self);let point=convert(event.locationInWindow,from:nil),map=mapPoint(point)
        if spaceHeld {spaceUsed=true;NSCursor.closedHand.set();drag=Drag(id:nil,start:point,offset:offset,original:placements,ids:[],manual:false,mode:.pan);return}
        for p in placements where parents.contains(p.id) && (selectedIDs.contains(p.id) || nodeMap[p.id]?.flag("collapsed")==true) {
            if CGRect(x:p.rect.maxX+3,y:portY(p)-9,width:18,height:18).contains(map){select(p.id);controller?.command("fold");return}
        }
        if let p=hit(map){
            if let from=connectFrom {connectFrom=nil;if from != p.id{controller?.addConnection(from:from,to:p.id)};return}
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command) {var ids=selectedIDs;if ids.contains(p.id){ids.remove(p.id)}else{ids.insert(p.id)};setSelection(ids,primary:p.id);return}
            if !selectedIDs.contains(p.id){select(p.id)}
            if event.clickCount==2 {edit(p.id);return}
            let ids=selectedIDs.reduce(into:Set<String>()){$0.formUnion(document.descendants($1))}
            drag=Drag(id:p.id,start:point,offset:offset,original:placements,ids:ids,manual:selectedIDs.count>1||event.modifierFlags.contains(.option)||nodeMap[p.id]?.parent==nil,selection:selectedIDs)
        } else {
            if event.clickCount==2,let c=hitConnection(map){controller?.editConnection(c);return}
            let previous=selectedIDs,base=event.modifierFlags.contains(.shift)||event.modifierFlags.contains(.command) ? previous:[]
            drag=Drag(id:nil,start:point,offset:offset,original:placements,ids:[],manual:false,mode:.marquee,selection:previous,baseSelection:base)
            setSelection(base)
        }
    }
    override func mouseDragged(with event:NSEvent){
        guard var d=drag else{return};let point=convert(event.locationInWindow,from:nil),dx=point.x-d.start.x,dy=point.y-d.start.y
        if d.mode == .pan {offset=CGPoint(x:d.offset.x+dx,y:d.offset.y+dy);needsDisplay=true;return}
        if hypot(dx,dy)>5{d.moved=true};guard d.moved else{return}
        if d.mode == .marquee {
            marquee=Self.selectionRect(from:d.start,to:point)
            let area=Self.selectionRect(from:mapPoint(d.start),to:mapPoint(point))
            setSelection(d.baseSelection.union(placements.filter{$0.rect.intersects(area)}.map(\.id)));drag=d;return
        }
        placements=d.original.map {p in var next=p;if d.ids.contains(p.id){next.rect.origin.x+=dx/zoom;next.rect.origin.y+=dy/zoom};return next}
        d.target=d.manual ? nil:placements.first{!d.ids.contains($0.id)&&$0.rect.insetBy(dx:-12,dy:-12).contains(mapPoint(point))}?.id
        drag=d;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent){
        guard let d=drag else{return};drag=nil;marquee=nil;needsDisplay=true;NSCursor.arrow.set();defer{refreshAX();controller?.checkPendingExternal()}
        guard d.mode == .nodes else{return}
        guard let id=d.id,d.moved else{return}
        let point=convert(event.locationInWindow,from:nil)
        if d.manual{controller?.translateSelection(d.selection,delta:CGPoint(x:(point.x-d.start.x)/zoom,y:(point.y-d.start.y)/zoom),placements:d.original)}
        else if let target=d.target{controller?.move(id,to:target)}else{placements=d.original;needsDisplay=true}
    }
    func cancelDrag(){if let d=drag{placements=d.original;offset=d.offset;drag=nil;marquee=nil;if d.mode == .marquee{setSelection(d.selection)};needsDisplay=true;refreshAX()};spaceHeld=false;spaceUsed=false;NSCursor.arrow.set()}
    override func resignFirstResponder()->Bool{spaceHeld=false;spaceUsed=false;NSCursor.arrow.set();return super.resignFirstResponder()}
    override func keyUp(with event:NSEvent){if event.keyCode==49{let editOnRelease=spaceHeld && !spaceUsed && drag==nil && selectedIDs.count==1;spaceHeld=false;spaceUsed=false;NSCursor.arrow.set();if editOnRelease{edit(selected)};return};super.keyUp(with:event)}
    override func scrollWheel(with event:NSEvent){guard editor==nil,drag==nil else{return};if event.modifierFlags.contains(.command)||event.modifierFlags.contains(.control){scale(exp(-event.scrollingDeltaY*0.01),at:convert(event.locationInWindow,from:nil))}else{offset.x-=event.scrollingDeltaX;offset.y-=event.scrollingDeltaY;needsDisplay=true;refreshAX()}}
    override func magnify(with event:NSEvent){guard editor==nil,drag==nil else{return};scale(1+event.magnification,at:convert(event.locationInWindow,from:nil))}
    override func keyDown(with event:NSEvent){
        if event.modifierFlags.contains(.command){super.keyDown(with:event);return}
        switch event.keyCode {
        case 48:controller?.command("child")
        case 36:controller?.command("sibling")
        case 49:if !event.isARepeat{spaceHeld=true;spaceUsed=false;NSCursor.openHand.set()}
        case 51,117:controller?.command("delete")
        case 53:let wasDragging=drag != nil;cancelDrag();connectFrom=nil;if !wasDragging,focus != nil{controller?.command("focus")}
        case 123,124,125,126:controller?.navigate(event.keyCode,reorder:event.modifierFlags.contains(.option))
        default:super.keyDown(with:event)
        }
    }
    func hitConnection(_ point:CGPoint)->Int?{
        let by=Dictionary(uniqueKeysWithValues:placements.map{($0.id,$0)})
        for (i,c) in document.connections.enumerated(){guard let a=by[c["from"] as? String ?? ""],let b=by[c["to"] as? String ?? ""] else{continue}
            let s=CGPoint(x:a.rect.midX,y:a.rect.minY),e=CGPoint(x:b.rect.midX,y:b.rect.minY),q=CGPoint(x:(a.rect.minX+b.rect.minX)/2,y:min(a.rect.minY,b.rect.minY)-70)
            for j in 0...60{let t=CGFloat(j)/60,u=1-t,p=CGPoint(x:u*u*s.x+2*u*t*q.x+t*t*e.x,y:u*u*s.y+2*u*t*q.y+t*t*e.y);if hypot(p.x-point.x,p.y-point.y)<8/zoom{return i}}
        };return nil
    }
    override func menu(for event:NSEvent)->NSMenu?{
        let p=mapPoint(convert(event.locationInWindow,from:nil)),menu=NSMenu()
        if let n=hit(p){if !selectedIDs.contains(n.id){select(n.id)};for (title,cmd) in [("编辑文字","edit"),("添加子节点","child"),("折叠 / 展开","fold"),("标记完成","done"),("插入图片","image"),("复制节点链接","copyLink"),("打开链接","openLink"),("删除分支","delete")]{let item=NSMenuItem(title:title,action:#selector(BranchController.menuCommand(_:)),keyEquivalent:"");item.representedObject=cmd;item.target=controller;menu.addItem(item)}}
        else if let index=hitConnection(p){let item=NSMenuItem(title:"删除关系线",action:#selector(BranchController.deleteConnectionMenu(_:)),keyEquivalent:"");item.tag=index;item.target=controller;menu.addItem(item)}
        else {
            let create=NSMenuItem(title:"新建主节点",action:#selector(BranchController.newRootMenu(_:)),keyEquivalent:"")
            create.target=controller;create.representedObject=NSValue(point:p);menu.addItem(create)
            let fit=NSMenuItem(title:"适配全部内容",action:#selector(BranchController.menuCommand(_:)),keyEquivalent:"");fit.target=controller;fit.representedObject="fit";menu.addItem(fit)
        }
        return menu
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{.copy}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool{
        guard let urls=sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty else{return false}
        if let p=hit(mapPoint(convert(sender.draggingLocation,from:nil))){select(p.id)}
        controller?.insertImages(urls);return true
    }
    func exportData(pdf:Bool) throws -> Data {
        let previous=placements;defer{placements=previous}
        placements=MindLayout.calculate(document);let b=contentBounds();guard b.width.isFinite,b.height.isFinite,b.width>0,b.height>0 else{throw BranchError("画布尺寸无效")}
        if pdf {
            let data=NSMutableData();var box=CGRect(origin:.zero,size:b.size);guard let consumer=CGDataConsumer(data:data),let cg=CGContext(consumer:consumer,mediaBox:&box,nil) else{throw BranchError("PDF 创建失败")}
            cg.beginPDFPage(nil);cg.translateBy(x:0,y:b.height);cg.scaleBy(x:1,y:-1);cg.translateBy(x:-b.minX,y:-b.minY)
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:cg,flipped:true);(document.theme=="light" ? NSColor.white:NSColor(hex:"#111112")).setFill();b.fill();drawScene(decorations:false);NSGraphicsContext.restoreGraphicsState();cg.endPDFPage();cg.closePDF();return data as Data
        }
        let scale=min(2,16000/b.width,16000/b.height,sqrt(64000000/(b.width*b.height))),w=max(1,Int(ceil(b.width*scale))),h=max(1,Int(ceil(b.height*scale)))
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else{throw BranchError("JPG 创建失败")}
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context.cgContext,flipped:true);let cg=context.cgContext;cg.translateBy(x:0,y:CGFloat(h));cg.scaleBy(x:scale,y:-scale);cg.translateBy(x:-b.minX,y:-b.minY);(document.theme=="light" ? NSColor.white:NSColor(hex:"#111112")).setFill();b.fill();drawScene(decorations:false);NSGraphicsContext.restoreGraphicsState()
        guard let result=bitmap.representation(using:.jpeg,properties:[.compressionFactor:0.95]) else{throw BranchError("JPG 编码失败")};return result
    }
}
