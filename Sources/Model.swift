import AppKit

struct BranchError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
func number(_ value: Any?, _ fallback: Double = 0) -> Double {
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String, let n = Double(s) { return n }
    return fallback
}
struct MindNode {
    var raw: [String: Any]
    var id: String { raw["id"] as? String ?? "" }
    var parent: String? { raw["parent"] as? String }
    var title: String { raw["title"] as? String ?? "" }
    func text(_ key: String) -> String { raw[key] as? String ?? "" }
    func flag(_ key: String) -> Bool { raw[key] as? Bool ?? false }
    var position: CGPoint? {
        guard let p = raw["position"] as? [String: Any] else { return nil }
        return CGPoint(x:number(p["x"]), y:number(p["y"]))
    }
    var fontSize: CGFloat { CGFloat(number(raw["fontSize"],16)) }
    var imageHeight: CGFloat { CGFloat(number(raw["imageSize"],150)) }
    var font: NSFont {
        switch text("fontFamily") {
        case "serif": return NSFont(name:"Songti SC",size:fontSize) ?? NSFont.systemFont(ofSize:fontSize)
        case "mono": return NSFont.monospacedSystemFont(ofSize:fontSize,weight:.regular)
        default: return NSFont.systemFont(ofSize:fontSize)
        }
    }
}
struct MindDocument {
    var raw: [String: Any]
    var nodes: [MindNode]
    init(raw: [String: Any]) { self.raw=raw; self.raw.removeValue(forKey:"nodes"); nodes=(raw["nodes"] as? [[String:Any]] ?? []).map { MindNode(raw:$0) } }
    var id: String { raw["id"] as? String ?? "" }
    var title: String { get { raw["title"] as? String ?? "未命名导图" } set { raw["title"]=newValue } }
    var revision: Int { get { Int(number(raw["revision"])) } set { raw["revision"]=newValue } }
    var roots: [MindNode] { children(nil) }
    var root: MindNode { roots.first! }
    var connections: [[String:Any]] { get { raw["connections"] as? [[String:Any]] ?? [] } set { raw["connections"]=newValue } }
    var theme: String { raw["theme"] as? String ?? "dark" }
    var layout: String { raw["layout"] as? String ?? "horizontal" }
    var json: [String:Any] { var result=raw;result["nodes"]=nodes.map(\.raw);return result }
    func data() throws -> Data { try JSONSerialization.data(withJSONObject:json,options:[.sortedKeys]) }
    func node(_ id: String) -> MindNode? { nodes.first {$0.id == id} }
    func children(_ id: String?) -> [MindNode] { nodes.filter {$0.parent == id}.sorted {number($0.raw["order"]) < number($1.raw["order"])} }
    mutating func set(_ id: String, _ key: String, _ value: Any?) { if let i=nodes.firstIndex(where:{$0.id==id}) {nodes[i].raw[key]=value} }
    func descendants(_ id: String) -> Set<String> {
        let children=Dictionary(grouping:nodes,by:{$0.parent ?? ""});var result:Set<String>=[id],stack=[id]
        while let p=stack.popLast() {for n in children[p] ?? [] where !result.contains(n.id) {result.insert(n.id);stack.append(n.id)}}
        return result
    }
    @discardableResult mutating func add(_ parent: String,title: String="新想法") -> String {
        let id=UUID().uuidString;nodes.append(MindNode(raw:["id":id,"parent":parent,"title":title,"order":children(parent).count]));set(parent,"collapsed",false);return id
    }
    @discardableResult mutating func addRoot(title:String="新主节点",at point:CGPoint?=nil) -> String {
        let id=UUID().uuidString,count=roots.count
        var raw:[String:Any]=["id":id,"parent":NSNull(),"title":title,"order":count,"color":MindLayout.palette[count % MindLayout.palette.count]]
        if let point {raw["position"]=["x":point.x,"y":point.y]}
        nodes.append(MindNode(raw:raw));self.raw["version"]=2;return id
    }
    mutating func remove(_ id: String) throws {
        guard let n=node(id) else{throw BranchError("节点不存在")}
        guard n.parent != nil || roots.count>1 else {throw BranchError("至少保留一个主节点")}
        let ids=descendants(id);nodes.removeAll {ids.contains($0.id)}
        connections.removeAll {ids.contains($0["from"] as? String ?? "") || ids.contains($0["to"] as? String ?? "")}
    }
    mutating func move(_ id: String,to parent: String,index: Int?=nil) throws {
        guard node(id)?.parent != nil else {throw BranchError("主节点只能整体移动")}
        guard node(parent) != nil,!descendants(id).contains(parent) else {throw BranchError("不能移入自己或自己的子节点")}
        var siblings=children(parent).filter {$0.id != id}.map(\.id)
        siblings.insert(id,at:min(max(0,index ?? siblings.count),siblings.count));set(id,"parent",parent)
        for (i,s) in siblings.enumerated() {set(s,"order",i)}
    }
    mutating func translate(_ id:String,by delta:CGPoint,origin:CGPoint) {
        let ids=descendants(id)
        for i in nodes.indices where ids.contains(nodes[i].id) {
            let p=nodes[i].id == id ? origin : nodes[i].position
            if let p {nodes[i].raw["position"]=["x":p.x+delta.x,"y":p.y+delta.y]}
        }
    }
    func selectionRoots(_ ids:Set<String>) -> [String] {
        let by=Dictionary(uniqueKeysWithValues:nodes.map{($0.id,$0)})
        return nodes.filter {n in
            guard ids.contains(n.id) else{return false}
            var parent=n.parent
            while let id=parent {if ids.contains(id){return false};parent=by[id]?.parent}
            return true
        }.map(\.id)
    }
    mutating func translateSelection(_ ids:Set<String>,by delta:CGPoint,placements:[NodePlacement]) {
        let positions=Dictionary(uniqueKeysWithValues:placements.map{($0.id,$0.rect.origin)})
        for id in selectionRoots(ids) {if let origin=positions[id]{translate(id,by:delta,origin:origin)}}
    }
    mutating func removeSelection(_ ids:Set<String>) throws {
        let tops=selectionRoots(ids)
        guard !roots.allSatisfy({tops.contains($0.id)}) else{throw BranchError("至少保留一个主节点")}
        for id in tops {try remove(id)}
    }
    static func create(_ title:String="未命名导图",sample:Bool=false) -> MindDocument {
        let id=UUID().uuidString,root=UUID().uuidString
        var d=MindDocument(raw:["version":1,"id":id,"revision":0,"title":title,"theme":"dark","layout":"horizontal","nodes":[["id":root,"parent":NSNull(),"title":title,"order":0,"color":"#f49b51"]],"connections":[]])
        if sample { for (i,title) in ["把想法写下来","理清它们的关系","慢慢变成行动"].enumerated() {let n=d.add(root,title:title);d.set(n,"color",MindLayout.palette[i]);d.add(n,title:["Tab 添加子节点","拖动节点调整结构","一切保存在本机"][i])} }
        return d
    }
}
struct NodePlacement {
    var id:String;var parent:String?;var rect:CGRect;var depth:Int;var color:String;var lines:[String];var font:NSFont
    var port:CGPoint {CGPoint(x:rect.maxX,y:rect.maxY)}
}
enum MindLayout {
    static let palette=["#f49b51","#7db49d","#8ba3d2","#bc93c5","#d9828e","#d5bf72"]
    static func lines(_ text:String,font:NSFont) -> [String] {
        var result=[String](),line="",width:CGFloat=0
        for ch in text.isEmpty ? " " : text {
            if ch == "\n" {result.append(line);line="";width=0;continue}
            let w=(String(ch) as NSString).size(withAttributes:[.font:font]).width
            if width+w > 240 && !line.isEmpty {result.append(line);line="";width=0}
            line.append(ch);width+=w
        }
        result.append(line);return result
    }
    static func calculate(_ d:MindDocument,focus:String?=nil) -> [NodePlacement] {
        let roots=focus.flatMap({d.node($0)}).map{[$0]} ?? d.roots
        guard !roots.isEmpty else{return []}
        let vertical=d.layout=="vertical",gap:CGFloat=d.layout=="compact" ? 14:27
        let groups=Dictionary(grouping:d.nodes,by:{$0.parent ?? ""}).mapValues {$0.sorted {number($0.raw["order"])<number($1.raw["order"])}}
        func kids(_ n:MindNode) -> [MindNode] {n.flag("collapsed") ? [] : groups[n.id] ?? []}
        struct Measure {var size:CGSize;var span:CGFloat;var lines:[String]}
        var sizes=[String:Measure]()
        @discardableResult func measure(_ n:MindNode) -> CGFloat {
            let rows=lines(n.title,font:n.font),w=rows.map {($0 as NSString).size(withAttributes:[.font:n.font]).width}.max() ?? 0
            let size=CGSize(width:max(n.text("image").isEmpty ? 70:210,min(280,w+26)),height:CGFloat(rows.count)*(n.fontSize+6)+(n.parent==nil ? 22:10)+(n.text("image").isEmpty ? 0:n.imageHeight+10))
            let list=kids(n),span=max(vertical ? size.width:size.height,list.reduce(CGFloat(0)) {$0+measure($1)}+CGFloat(max(0,list.count-1))*gap)
            sizes[n.id]=Measure(size:size,span:span,lines:rows);return span
        }
        for root in roots{measure(root)};var result=[NodePlacement]()
        func place(_ n:MindNode,_ major:CGFloat,_ cross:CGFloat,_ depth:Int,_ color:String,_ offset:CGPoint) {
            guard let s=sizes[n.id] else{return}
            let auto=CGPoint(x:vertical ? cross+s.span/2-s.size.width/2:major,y:vertical ? major:cross+s.span/2-s.size.height/2)
            let point=n.position ?? CGPoint(x:auto.x+offset.x,y:auto.y+offset.y),c=n.text("color").isEmpty ? color:n.text("color")
            result.append(NodePlacement(id:n.id,parent:n.parent,rect:CGRect(origin:point,size:s.size),depth:depth,color:c,lines:s.lines,font:n.font))
            var top=cross
            for k in kids(n) {place(k,major+(vertical ? s.size.height:s.size.width)+64,top,depth+1,c,CGPoint(x:point.x-auto.x,y:point.y-auto.y));top+=sizes[k.id]!.span+gap}
        }
        var cross:CGFloat=0
        for (i,root) in roots.enumerated(){
            place(root,0,cross,0,root.text("color").isEmpty ? palette[i % palette.count]:root.text("color"),.zero)
            cross+=(sizes[root.id]?.span ?? 0)+120
        }
        return result
    }
}
extension NSColor {
    convenience init(hex:String) {let s=hex.trimmingCharacters(in:CharacterSet(charactersIn:"#"));let value=UInt64(s,radix:16) ?? 0xf49b51;self.init(calibratedRed:CGFloat((value>>16)&255)/255,green:CGFloat((value>>8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)}
    var hex:String {guard let c=usingColorSpace(.deviceRGB) else{return "#f49b51"};return String(format:"#%02x%02x%02x",Int(c.redComponent*255),Int(c.greenComponent*255),Int(c.blueComponent*255))}
}
