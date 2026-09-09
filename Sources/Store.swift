import Foundation
import Darwin

final class DocumentStore {
    let root:URL
    init(root:URL?=nil) {
        self.root=root ?? ProcessInfo.processInfo.environment["BRANCH_HOME"].map {URL(fileURLWithPath:$0)} ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/枝图",isDirectory:true)
    }
    static func validID(_ id:String) -> Bool {id.range(of:"^[a-zA-Z0-9-]{1,80}$",options:.regularExpression) != nil}
    func path(_ id:String) throws -> URL {guard Self.validID(id) else{throw BranchError("无效文档 ID")};return root.appendingPathComponent(id+".branch")}
    func prepare() throws {try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
    static func decode(_ data:Data) throws -> MindDocument {
        guard let raw=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw BranchError("工程格式无效")}
        let d=MindDocument(raw:raw);try validate(d);return d
    }
    static func validate(_ d:MindDocument,images:Bool=true) throws {
        guard [1.0,2.0].contains(number(d.raw["version"])),validID(d.id),d.raw["title"] is String else {throw BranchError("工程版本、ID 或名称无效")}
        guard !d.nodes.isEmpty,d.nodes.count<=10000,Set(d.nodes.map(\.id)).count==d.nodes.count,!d.roots.isEmpty,(number(d.raw["version"])==2 || d.roots.count==1) else {throw BranchError("节点数量、ID 或主节点无效")}
        let by=Dictionary(uniqueKeysWithValues:d.nodes.map {($0.id,$0)})
        for n in d.nodes {
            guard validID(n.id),n.raw["title"] is String else{throw BranchError("节点 ID 或标题无效")}
            for key in ["notes","tags","link","color","shape","fontFamily","lineStyle"] where n.raw[key] != nil {guard n.raw[key] is String else{throw BranchError(key+" 必须是文本")}}
            guard (8...96).contains(n.fontSize),(60...240).contains(n.imageHeight) else{throw BranchError("字号或图片尺寸超出范围")}
            if let p=n.position {guard p.x.isFinite,p.y.isFinite else{throw BranchError("节点位置无效")}}
            var seen=Set<String>(),cur=n
            while let parent=cur.parent {
                guard !seen.contains(cur.id),seen.count<128,let next=by[parent] else {throw BranchError("层级循环、过深或父节点不存在")}
                seen.insert(cur.id);cur=next
            }
            let image=n.text("image")
            if images && !image.isEmpty {guard image.hasPrefix("data:image/jpeg;base64,"),let data=Data(base64Encoded:String(image.dropFirst(23))),data.starts(with:[255,216,255]),data.suffix(2)==Data([255,217]) else{throw BranchError("工程图片必须是有效 JPG")}}
        }
        for c in d.connections {guard let from=c["from"] as? String,let to=c["to"] as? String,by[from] != nil,by[to] != nil else{throw BranchError("关系线引用不存在的节点")}}
    }
    func read(_ id:String) throws -> MindDocument {
        let url=try path(id)
        do {return try Self.decode(Data(contentsOf:url))} catch {
            let backup=url.deletingPathExtension().appendingPathExtension("backup")
            guard FileManager.default.fileExists(atPath:backup.path) else{throw error}
            var d=try Self.decode(Data(contentsOf:backup));d.raw["_recovered"]=true;return d
        }
    }
    struct Entry {let id:String;let title:String;let revision:Int;let modified:Date}
    func list() throws -> [Entry] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.contentModificationDateKey]).filter {$0.pathExtension=="branch"}.map {url in
            let d=try? read(url.deletingPathExtension().lastPathComponent)
            return Entry(id:url.deletingPathExtension().lastPathComponent,title:d?.title ?? url.lastPathComponent+"（文件损坏）",revision:d?.revision ?? -1,modified:(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted {$0.modified>$1.modified}
    }
    func save(_ document:MindDocument,expected:Int) throws -> MindDocument {
        try Self.validate(document);try prepare()
        let fd=Darwin.open(root.appendingPathComponent(".lock").path,O_CREAT|O_RDWR,0o600)
        guard fd>=0 else{throw BranchError("无法打开文档锁")};defer{flock(fd,LOCK_UN);Darwin.close(fd)}
        guard flock(fd,LOCK_EX)==0 else{throw BranchError("无法锁定工程")}
        let url=try path(document.id),old=FileManager.default.fileExists(atPath:url.path) ? try read(document.id):nil
        guard (old?.revision ?? 0)==expected else{throw BranchError("版本冲突：工程已由 MCP 或其他窗口修改。请导出副本后重新载入。")}
        if let old {try atomic(old.data(),to:url.deletingPathExtension().appendingPathExtension("backup"))}
        var d=document;d.revision=expected+1;d.raw.removeValue(forKey:"_recovered");try atomic(d.data(),to:url);return d
    }
    private func atomic(_ data:Data,to url:URL) throws {
        let tmp=root.appendingPathComponent(".pending-"+UUID().uuidString)
        let fd=Darwin.open(tmp.path,O_CREAT|O_EXCL|O_WRONLY,0o600)
        guard fd>=0 else{throw BranchError("无法创建临时工程")}
        defer{Darwin.close(fd);try? FileManager.default.removeItem(at:tmp)}
        try data.withUnsafeBytes {bytes in
            var written=0
            while written<data.count {let count=Darwin.write(fd,bytes.baseAddress!.advanced(by:written),data.count-written);guard count>0 else{throw BranchError("工程写入失败")};written+=count}
        }
        guard fsync(fd)==0,rename(tmp.path,url.path)==0 else{throw BranchError("工程写入失败")}
        let dir=Darwin.open(root.path,O_RDONLY);if dir>=0{_ = fsync(dir);Darwin.close(dir)}
    }
}
final class StoreWatcher {
    private var source:DispatchSourceFileSystemObject?
    init(url:URL,onChange:@escaping ()->Void) throws {
        let fd=Darwin.open(url.path,O_EVTONLY);guard fd>=0 else{throw BranchError("无法监听工程目录")}
        let source=DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:[.write,.rename,.delete],queue:.main)
        source.setEventHandler(handler:onChange);source.setCancelHandler{Darwin.close(fd)};source.resume();self.source=source
    }
    deinit{source?.cancel()}
}
