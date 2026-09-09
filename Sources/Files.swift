import AppKit
import UniformTypeIdentifiers
extension BranchController {
    func open(_ url:URL){
        guard window != nil else{deferredOpen.append(url);return}
        if url.scheme=="branch"{if let id=url.host{showDocument(id,node:url.pathComponents.dropFirst().first)};return}
        afterSaved{[weak self] in guard let self else{return};do{
            let ext=url.pathExtension.lowercased();if ext=="mindnode"{throw BranchError("MindNode 原生导入尚待真实样本验证。请先从 MindNode 导出 OPML 迁入；原文件不会修改。")}
            let data=try Data(contentsOf:url);var d:MindDocument
            if ext=="branch"{d=try DocumentStore.decode(data);d.raw["id"]=UUID().uuidString;d.revision=0;d.raw.removeValue(forKey:"_recovered")}
            else if ext=="opml"{d=try Exchange.fromOPML(data)}else{guard let text=String(data:data,encoding:.utf8) else{throw BranchError("文件不是 UTF-8 文本")};d=try Exchange.fromMarkdown(text)}
            self.load(d);self.dirty=true;self.save();self.canvas.fit()
        }catch{self.alert(error)}}
    }
    func insertImages(_ urls:[URL]){
        commitEditing();let id=selected,docID=document.id
        io.async{[weak self] in guard let self else{return};do{
            var images=[String]()
            for url in urls{
                let temp=FileManager.default.temporaryDirectory.appendingPathComponent("branch-image-"+UUID().uuidString+".jpg");defer{try? FileManager.default.removeItem(at:temp)}
                try jpegFile(url,temp);images.append("data:image/jpeg;base64,"+(try Data(contentsOf:temp)).base64EncodedString())
            }
            DispatchQueue.main.async{guard self.document.id==docID,self.document.node(id) != nil else{return};if let image=images.last{self.mutate{$0.set(id,"image",image);$0.set(id,"imageSize",150)}}}
        }catch{DispatchQueue.main.async{self.alert(error)}}}
    }
    func exportMenu(){let a=NSAlert();a.messageText="导出导图";a.informativeText="JPG、PDF 导出完整导图。工程副本保留全部内容；Markdown、OPML 仅保留标题和层级。";a.addButton(withTitle:"导出");a.addButton(withTitle:"取消");let popup=NSPopUpButton(frame:CGRect(x:0,y:0,width:300,height:28));popup.addItems(withTitles:["JPG 图片","PDF 文档","完整工程副本 (.branch)","Markdown","OPML"]);a.accessoryView=popup;if a.runModal() == .alertFirstButtonReturn{export(["jpg","pdf","branch","md","opml"][popup.indexOfSelectedItem])}}
    func export(_ format:String){
        commitEditing();let panel=NSSavePanel();panel.nameFieldStringValue=document.title+"."+format;panel.allowedContentTypes=[UTType(filenameExtension:format) ?? .data]
        panel.beginSheetModal(for:window){[weak self] response in guard let self,response == .OK,let url=panel.url else{return};do{
            let data:Data
            switch format{case "jpg","pdf":data=try self.canvas.exportData(pdf:format=="pdf");case "branch":data=try self.document.data();case "opml":data=Exchange.opml(self.document);default:data=Data(Exchange.markdown(self.document).utf8)}
            try data.write(to:url,options:.atomic);self.saveLabel.stringValue="导出完成"
        }catch{self.alert(error)}}
    }
}
