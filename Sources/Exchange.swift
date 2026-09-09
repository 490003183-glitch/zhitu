import Foundation

enum Exchange {
    static func markdown(_ d:MindDocument)->String {
        var rows=[String]();func visit(_ n:MindNode,_ depth:Int){rows.append(String(repeating:"  ",count:depth)+"- "+n.title.replacingOccurrences(of:"\n",with:"<br>"));for c in d.children(n.id){visit(c,depth+1)}};for root in d.roots{visit(root,0)};return rows.joined(separator:"\n")
    }
    static func fromMarkdown(_ text:String) throws -> MindDocument {
        var d=MindDocument.create(),stack=[String](),hasRoot=false
        let regex=try NSRegularExpression(pattern:"^(\\s*)(?:[-*+]\\s+|\\d+\\.\\s+|#+\\s+)(.*)$")
        for line in text.components(separatedBy:.newlines) where !line.trimmingCharacters(in:.whitespaces).isEmpty {
            let ns=line as NSString,match=regex.firstMatch(in:line,range:NSRange(location:0,length:ns.length));let indent=match.map{ns.substring(with:$0.range(at:1)).replacingOccurrences(of:"\t",with:"  ").count} ?? 0
            let title=(match.map{ns.substring(with:$0.range(at:2))} ?? line.trimmingCharacters(in:.whitespaces)).replacingOccurrences(of:"<br>",with:"\n")
            if !hasRoot {d.set(d.root.id,"title",title);d.title=title;stack=[d.root.id];hasRoot=true;continue}
            if indent==0 {let id=d.addRoot(title:title);stack=[id];continue}
            let depth=max(1,min(indent/2,stack.count)),id=d.add(stack[depth-1],title:title);stack=Array(stack.prefix(depth));stack.append(id)
        }
        guard hasRoot else{throw BranchError("文件没有节点")};try DocumentStore.validate(d);return d
    }
    static func opml(_ d:MindDocument)->Data {
        func outline(_ n:MindNode)->XMLElement {let e=XMLElement(name:"outline");e.addAttribute(XMLNode.attribute(withName:"text",stringValue:n.title) as! XMLNode);for c in d.children(n.id){e.addChild(outline(c))};return e}
        let root=XMLElement(name:"opml");root.addAttribute(XMLNode.attribute(withName:"version",stringValue:"2.0") as! XMLNode);let head=XMLElement(name:"head");head.addChild(XMLElement(name:"title",stringValue:d.title));root.addChild(head);let body=XMLElement(name:"body");for r in d.roots{body.addChild(outline(r))};root.addChild(body);let xml=XMLDocument(rootElement:root);xml.characterEncoding="UTF-8";return xml.xmlData(options:.nodePrettyPrint)
    }
    static func fromOPML(_ data:Data) throws -> MindDocument {
        let xml=try XMLDocument(data:data,options:[.nodeLoadExternalEntitiesNever]);guard let body=xml.rootElement()?.elements(forName:"body").first else{throw BranchError("OPML 缺少 body")};let roots=body.elements(forName:"outline");guard !roots.isEmpty else{throw BranchError("文件没有节点")}
        var d=MindDocument.create("导入文档")
        func visit(_ e:XMLElement,_ parent:String,_ depth:Int) throws {guard depth<=128 else{throw BranchError("节点层级超过 128")};let id=d.add(parent,title:e.attribute(forName:"text")?.stringValue ?? e.attribute(forName:"title")?.stringValue ?? "");guard d.nodes.count<=10000 else{throw BranchError("节点超过 10000")};for c in e.elements(forName:"outline"){try visit(c,id,depth+1)}}
        for (i,r) in roots.enumerated(){
            let title=r.attribute(forName:"text")?.stringValue ?? r.attribute(forName:"title")?.stringValue ?? "导入文档"
            let id:String
            if i==0{id=d.root.id;d.title=title;d.set(id,"title",title)}else{id=d.addRoot(title:title)}
            for c in r.elements(forName:"outline"){try visit(c,id,1)}
        }
        if let title=xml.rootElement()?.elements(forName:"head").first?.elements(forName:"title").first?.stringValue,!title.isEmpty{d.title=title}
        try DocumentStore.validate(d);return d
    }
}
