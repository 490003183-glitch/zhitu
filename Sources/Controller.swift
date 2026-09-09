import AppKit
import UniformTypeIdentifiers

final class BranchController:NSObject,NSWindowDelegate,NSOutlineViewDataSource,NSOutlineViewDelegate,NSSearchFieldDelegate {
    let store=DocumentStore(),io=DispatchQueue(label:"branch.store",qos:.utility)
    var window:NSWindow!,rootView:RootView!,header=HeaderView(),canvas=MindCanvas(),footer=FlippedView()
    var titleField:ActionField!,saveLabel:NSTextField!,stats=label(""),zoomButton:ActionButton!,searchField=NSSearchField()
    var libraryScroll=NSScrollView(),inspectorScroll=NSScrollView(),outlineScroll=NSScrollView(),outline=NativeOutline()
    var toolbarButtons=[ActionButton](),rightButtons=[ActionButton](),sidebarButton:ActionButton!
    var document=MindDocument.create(),selected="",focusID:String?,library=[DocumentStore.Entry]()
    var history=[MindDocument](),future=[MindDocument](),dirty=false,saving=false,generation=0
    var saveWork:DispatchWorkItem?,watchWork:DispatchWorkItem?,watcher:StoreWatcher?,pendingExternal=false
    var saveCallbacks=[(Bool)->Void](),allowClose=false,committing=false,refreshing=false
    var showLibrary=false,showInspector=false,showOutline=false,showSearch=false,inspectorTab=0
    var outlineNodes=[String:NSString](),deferredOpen=[URL]()
    func start(){
        makeMenu();window=NSWindow(contentRect:NSRect(x:0,y:0,width:1440,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="枝图";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.minSize=CGSize(width:1000,height:650);window.delegate=self;window.appearance=NSAppearance(named:.darkAqua)
        rootView=RootView(frame:NSRect(x:0,y:0,width:1440,height:900));rootView.onLayout={[weak self] in self?.layoutViews()};window.contentView=rootView
        canvas.controller=self
        for v in [header,canvas,footer,libraryScroll,inspectorScroll,outlineScroll,searchField]{rootView.addSubview(v)}
        for scroll in [libraryScroll,inspectorScroll,outlineScroll]{scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false}
        sidebarButton=button("文档与大纲","sidebar.left","library");header.addSubview(sidebarButton)
        titleField=ActionField("",placeholder:"文档名称"){[weak self] value in let title=value.isEmpty ? "未命名导图":value;if self?.document.title != title{self?.mutate{d in d.title=title}}};titleField.isBordered=false;titleField.drawsBackground=false;titleField.font = .systemFont(ofSize:13,weight:.semibold);header.addSubview(titleField)
        saveLabel=label("已保存到本机",size:10);header.addSubview(saveLabel)
        for (name,symbol,cmd) in [("添加子节点 · Tab","plus.square.on.square","child"),("添加同级节点 · Enter","plus.square","sibling"),("标记为任务","checkmark.circle","task"),("连接两个节点","point.topleft.down.to.point.bottomright.curvepath","connect"),("聚焦 / 返回全图","arrow.up.left.and.arrow.down.right","focus"),("折叠 / 展开","chevron.right.circle","fold"),("备注","note.text","notes"),("标签","tag","tags"),("插入图片 · PNG 自动转 JPG","photo","image")]{let b=button(name,symbol,cmd);toolbarButtons.append(b);header.addSubview(b)}
        for (name,symbol,cmd) in [("撤销 · ⌘Z","arrow.uturn.backward","undo"),("重做 · ⇧⌘Z","arrow.uturn.forward","redo"),("搜索","magnifyingglass","search"),("导出 JPG / PDF","square.and.arrow.up","export"),("显示检查器","sidebar.right","inspector")]{let b=button(name,symbol,cmd);rightButtons.append(b);header.addSubview(b)}
        let minus=button("缩小","minus","zoomOut"),plus=button("放大","plus","zoomIn"),help=button("快捷键","questionmark.circle","help")
        minus.identifier=NSUserInterfaceItemIdentifier("minus");plus.identifier=NSUserInterfaceItemIdentifier("plus");help.identifier=NSUserInterfaceItemIdentifier("help")
        zoomButton=ActionButton("100%",action:{[weak self] in self?.canvas.fit()});zoomButton.isBordered=false;zoomButton.setAccessibilityLabel("适配全部内容");zoomButton.font = .systemFont(ofSize:11)
        for v in [minus,zoomButton!,plus,stats,help]{footer.addSubview(v)}
        searchField.placeholderString="搜索标题或标签";searchField.delegate=self;searchField.setAccessibilityLabel("搜索节点");searchField.sendsSearchStringImmediately=true
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("title"));column.title="大纲";outline.addTableColumn(column);outline.outlineTableColumn=column;column.isEditable=true;outline.controller=self;outline.target=self;outline.doubleAction=#selector(editOutline);outline.headerView=nil;outline.delegate=self;outline.dataSource=self;outline.rowHeight=34;outline.indentationPerLevel=23;outline.selectionHighlightStyle = .regular;outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle;outlineScroll.documentView=outline
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);layoutViews()
        do {try store.prepare();library=try store.list();if let first=library.first{load(try store.read(first.id))}else{load(MindDocument.create("留一片地方，给想法",sample:true));dirty=true;save()};watcher=try StoreWatcher(url:store.root){[weak self] in self?.scheduleExternalCheck()}}catch{alert(error)}
        layoutViews();window.makeFirstResponder(canvas);for url in deferredOpen{open(url)};deferredOpen=[]
    }
    func button(_ name:String,_ symbol:String,_ command:String)->ActionButton{ActionButton(name,symbol:symbol){[weak self] in self?.command(command)}}
    func layoutViews(){
        let w=rootView.bounds.width,h=rootView.bounds.height,left:CGFloat=showLibrary ? 235:0,right:CGFloat=showInspector ? 280:0
        header.frame=CGRect(x:0,y:0,width:w,height:54);sidebarButton.frame=CGRect(x:80,y:11,width:32,height:30);titleField.frame=CGRect(x:125,y:9,width:min(220,max(140,w*0.15)),height:20);saveLabel.frame=CGRect(x:125,y:30,width:230,height:15)
        let buttonWidth:CGFloat=w<1150 ? 29:34,total=CGFloat(toolbarButtons.count)*buttonWidth,start=max(335,(w-total)/2)
        for (i,b) in toolbarButtons.enumerated(){b.frame=CGRect(x:start+CGFloat(i)*buttonWidth,y:12,width:buttonWidth-2,height:30)}
        for (i,b) in rightButtons.enumerated(){b.frame=CGRect(x:w-15-CGFloat(rightButtons.count-i)*32,y:12,width:30,height:30)}
        libraryScroll.frame=CGRect(x:0,y:54,width:left,height:h-54);libraryScroll.isHidden = !showLibrary
        inspectorScroll.frame=CGRect(x:w-right,y:54,width:right,height:h-54);inspectorScroll.isHidden = !showInspector
        let area=CGRect(x:left,y:54,width:max(100,w-left-right),height:h-84);canvas.frame=area;outlineScroll.frame=area;canvas.isHidden=showOutline;outlineScroll.isHidden = !showOutline
        footer.frame=CGRect(x:left,y:h-30,width:area.width,height:30)
        footer.subviews.first{$0.identifier?.rawValue=="minus"}?.frame=CGRect(x:12,y:1,width:25,height:25);zoomButton.frame=CGRect(x:39,y:2,width:52,height:23);footer.subviews.first{$0.identifier?.rawValue=="plus"}?.frame=CGRect(x:93,y:1,width:25,height:25);stats.frame=CGRect(x:135,y:7,width:max(100,area.width-200),height:18);footer.subviews.first{$0.identifier?.rawValue=="help"}?.frame=CGRect(x:area.width-35,y:1,width:25,height:25)
        searchField.frame=CGRect(x:w-right-290,y:68,width:270,height:28);searchField.isHidden = !showSearch
    }
    func makeMenu(){
        let menu=NSMenu();NSApp.mainMenu=menu
        func section(_ name:String)->NSMenu{let i=NSMenuItem();i.title=name;let m=NSMenu(title:name);i.submenu=m;menu.addItem(i);return m}
        func item(_ menu:NSMenu,_ title:String,_ key:String="",_ command:String){let i=NSMenuItem(title:title,action:#selector(menuCommand(_:)),keyEquivalent:key);i.target=self;i.representedObject=command;menu.addItem(i)}
        let app=section("枝图");item(app,"关于枝图","","about");app.addItem(.separator());app.addItem(withTitle:"隐藏枝图",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h");app.addItem(.separator());app.addItem(withTitle:"退出枝图",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let file=section("文件");item(file,"新建导图","n","new");item(file,"打开 / 导入…","o","open");item(file,"保存","s","save");item(file,"导出…","e","export");file.addItem(.separator());file.addItem(withTitle:"关闭窗口",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        let edit=section("编辑");item(edit,"撤销","z","undo");item(edit,"重做","Z","redo");edit.addItem(.separator());for (title,selector,key) in [("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")]{edit.addItem(withTitle:title,action:Selector(selector),keyEquivalent:key)};item(edit,"查找","f","search")
        let node=section("节点");for (title,cmd) in [("新建主节点","newRoot"),("添加子节点","child"),("添加同级节点","sibling"),("编辑标题","edit"),("删除分支","delete"),("折叠 / 展开","fold"),("标记为任务","task"),("完成 / 未完成","done"),("连接两个节点","connect"),("插入图片…","image"),("复制节点链接","copyLink"),("打开节点链接","openLink")]{item(node,title,"",cmd)}
        let view=section("视图");for (title,cmd) in [("文档栏","library"),("检查器","inspector"),("导图 / 大纲","outline"),("聚焦 / 返回全图","focus"),("适配全部内容","fit"),("放大","zoomIn"),("缩小","zoomOut"),("重新自动布局","reset")]{item(view,title,"",cmd)}
        let help=section("帮助");item(help,"快捷键","","help");item(help,"本地连接 / MCP","","mcp");item(help,"保存冲突恢复…","","recovery")
    }
    @objc func menuCommand(_ sender:NSMenuItem){if let cmd=sender.representedObject as? String{command(cmd)}}
    @objc func newRootMenu(_ sender:NSMenuItem){
        guard let point=sender.representedObject as? NSValue else{return};createRoot(at:point.pointValue)
    }
    func createRoot(at point:CGPoint){
        commitEditing();var id="";mutate{d in id=d.addRoot(at:point)}
        guard document.node(id) != nil else{return}
        focusID=nil;selected=id;refresh();if showOutline{beginOutlineEdit(id)}else{canvas.edit(id)}
    }
    func load(_ d:MindDocument){document=d;selected=d.root.id;focusID=nil;history=[];future=[];generation+=1;dirty=d.raw["_recovered"] as? Bool ?? false;refresh();canvas.fit();if dirty{saveLabel.stringValue="已从备份恢复 · 请保存"}}
    func refresh(){
        refreshing=true;defer{refreshing=false}
        if document.node(selected)==nil{selected=document.root.id};if let focusID,document.node(focusID)==nil{self.focusID=nil};titleField?.stringValue=document.title
        window?.appearance=NSAppearance(named:document.theme=="light" ? .aqua:.darkAqua)
        canvas.reload(document,selection:selected,focus:focusID);rightButtons.first?.isEnabled = !history.isEmpty;if rightButtons.count>1{rightButtons[1].isEnabled = !future.isEmpty}
        refreshOutline();if showInspector{buildInspector()};if showLibrary{buildLibrary()};updateFooter()
    }
    func updateFooter(){zoomButton?.title="\(Int((canvas.zoom*100).rounded()))%";stats.stringValue="\(document.nodes.count) 个节点 · \(document.nodes.filter{!$0.text("image").isEmpty}.count) 张图片"+(canvas.selectedIDs.count>1 ? " · 已选 \(canvas.selectedIDs.count) 个":"")+(focusID == nil ? "":" · 聚焦视图")}
    func select(_ id:String){guard document.node(id) != nil else{return};selected=id;canvas.selected=id;canvas.selectedIDs=[id];canvas.needsDisplay=true;updateFooter();if showInspector{buildInspector()};if showOutline,let item=outlineNodes[id]{let row=outline.row(forItem:item);if row>=0{outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}}}
    func commitEditing(){guard !committing else{return};committing=true;canvas.commitEditor();window?.makeFirstResponder(showOutline ? outline:canvas);committing=false}
    func mutate(_ edit:(inout MindDocument)throws->Void){
        let old=document
        do {try edit(&document);try DocumentStore.validate(document,images:false)}catch{document=old;alert(error);return}
        history.append(old);if history.count>80{history.removeFirst()};future=[];generation+=1;dirty=true;saveLabel.stringValue="尚未保存…";refresh();scheduleSave()
    }
    func editNode(_ id:String,key:String,value:Any?){guard let n=document.node(id) else{return};if let s=value as? String,n.text(key)==s{return};mutate{$0.set(id,key,value)}}
    func translate(_ id:String,delta:CGPoint,origin:CGPoint){mutate{$0.translate(id,by:delta,origin:origin)}}
    func translateSelection(_ ids:Set<String>,delta:CGPoint,placements:[NodePlacement]){mutate{$0.translateSelection(ids,by:delta,placements:placements)}}
    func move(_ id:String,to parent:String){mutate{try $0.move(id,to:parent);$0.set(parent,"collapsed",false)}}
    func undo(_ redo:Bool=false){
        if let text=window.firstResponder as? NSTextView,text !== canvas.editor,let undo=text.undoManager,(redo ? undo.canRedo:undo.canUndo){if redo{undo.redo()}else{undo.undo()};return}
        commitEditing();let previous=redo ? future.popLast():history.popLast();guard var d=previous else{return};if redo{history.append(document)}else{future.append(document)};d.revision=document.revision;document=d;generation+=1;dirty=true;refresh();scheduleSave()
    }
    func scheduleSave(){saveWork?.cancel();let work=DispatchWorkItem{[weak self] in self?.save()};saveWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)}
    func save(completion:((Bool)->Void)?=nil){
        saveWork?.cancel();if let completion{saveCallbacks.append(completion)};if saving{return}
        guard dirty else{let callbacks=saveCallbacks;saveCallbacks=[];callbacks.forEach{$0(true)};return}
        let snapshot=document,stamp=generation;saving=true;saveLabel.stringValue="正在保存…"
        io.async {[weak self] in guard let self else{return};let result=Result{try self.store.save(snapshot,expected:snapshot.revision)}
            DispatchQueue.main.async {self.saving=false;switch result {
            case .success(let saved):self.document.revision=saved.revision;self.document.raw.removeValue(forKey:"_recovered");self.dirty=self.generation != stamp;self.saveLabel.stringValue=self.dirty ? "继续保存…":"已保存到本机";if self.dirty{self.save();return};self.refreshLibrary();let callbacks=self.saveCallbacks;self.saveCallbacks=[];callbacks.forEach{$0(true)};self.checkPendingExternal()
            case .failure(let error):self.saveLabel.stringValue="保存失败 · 帮助菜单可导出副本";let callbacks=self.saveCallbacks;self.saveCallbacks=[];callbacks.forEach{$0(false)};self.alert(error)
            }}
        }
    }
    func afterSaved(_ action:@escaping()->Void){commitEditing();save{ok in if ok{action()}}}
    func windowShouldClose(_ sender:NSWindow)->Bool{if allowClose{return true};afterSaved{[weak self] in guard let self else{return};self.allowClose=true;self.window.close()};return false}
    func windowWillUseStandardFrame(_ window:NSWindow,defaultFrame newFrame:NSRect)->NSRect{window.screen?.visibleFrame ?? newFrame}
    func windowDidResignKey(_ notification:Notification){canvas.cancelDrag()}
    func terminate()->NSApplication.TerminateReply{if allowClose{return .terminateNow};commitEditing();if !dirty && !saving{return .terminateNow};DispatchQueue.main.async{self.save{ok in NSApp.reply(toApplicationShouldTerminate:ok)}};return .terminateLater}
    func scheduleExternalCheck(){watchWork?.cancel();pendingExternal=true;let w=DispatchWorkItem{[weak self] in self?.checkPendingExternal()};watchWork=w;DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:w)}
    func checkPendingExternal(){
        guard pendingExternal,!dirty,!saving,canvas.drag==nil,canvas.editor==nil,!(window.firstResponder is NSTextView) else{return};pendingExternal=false
        let id=document.id
        io.async {[weak self] in guard let self else{return};let latest=try? self.store.read(id),list=try? self.store.list();DispatchQueue.main.async{guard self.document.id==id else{return};if let list{self.library=list;if self.showLibrary{self.buildLibrary()}};guard let latest,latest.revision != self.document.revision else{return};if self.dirty||self.saving||self.canvas.drag != nil||self.canvas.editor != nil{self.pendingExternal=true;return};let selected=self.selected,focus=self.focusID;self.document=latest;self.selected=selected;self.focusID=focus;self.history=[];self.future=[];self.refresh();self.saveLabel.stringValue="已同步 MCP / 外部修改"}}
    }
    func refreshLibrary(){io.async{[weak self] in guard let self,let list=try? self.store.list() else{return};DispatchQueue.main.async{self.library=list;if self.showLibrary{self.buildLibrary()}}}}
    func showDocument(_ id:String,node:String?=nil){afterSaved{[weak self] in guard let self else{return};do{self.load(try self.store.read(id));if let node,self.document.node(node) != nil{var p=self.document.node(node)?.parent;while let id=p{self.document.set(id,"collapsed",false);p=self.document.node(id)?.parent};self.select(node);self.refresh();self.canvas.fit()}}catch{self.alert(error)}}}
    func command(_ cmd:String){
        if cmd=="undo"{undo();return};if cmd=="redo"{undo(true);return}
        commitEditing()
        if !showOutline,canvas.selectedIDs.isEmpty,["child","sibling","delete","edit","fold","task","done","connect","notes","tags","image","copyLink","openLink"].contains(cmd){return}
        switch cmd {
        case "newRoot":createRoot(at:canvas.mapPoint(CGPoint(x:canvas.bounds.midX,y:canvas.bounds.midY)))
        case "child","sibling":let n=document.node(selected) ?? document.root;var id="";mutate{d in let parent=cmd=="sibling" ? n.parent ?? n.id:n.id;id=d.add(parent);if cmd=="sibling",n.parent != nil{let i=d.children(parent).firstIndex{$0.id==n.id} ?? 0;try d.move(id,to:parent,index:i+1)}};selected=id;refresh();if showOutline{beginOutlineEdit(id)}else{canvas.edit(id)}
        case "delete":let ids=canvas.selectedIDs,parent=document.node(selected)?.parent;mutate{try $0.removeSelection(ids)};if let parent,document.node(parent) != nil{select(parent)}
        case "edit":if showOutline{beginOutlineEdit(selected)}else{canvas.edit(selected)}
        case "fold":editNode(selected,key:"collapsed",value:!(document.node(selected)?.flag("collapsed") ?? false))
        case "task":editNode(selected,key:"task",value:!(document.node(selected)?.flag("task") ?? false))
        case "done":mutate{$0.set(selected,"task",true);$0.set(selected,"done",!($0.node(selected)?.flag("done") ?? false))}
        case "connect":canvas.connectFrom=selected;saveLabel.stringValue="点击另一节点建立关系线"
        case "focus":focusID=focusID==nil ? selected:nil;refresh();canvas.fit()
        case "reset":mutate{d in for n in d.nodes{d.set(n.id,"position",nil)}};canvas.fit()
        case "fit":canvas.fit()
        case "zoomIn":canvas.scale(1.2)
        case "zoomOut":canvas.scale(1/1.2)
        case "library":showLibrary.toggle();buildLibrary();layoutViews()
        case "inspector":showInspector.toggle();buildInspector();layoutViews()
        case "notes","tags":inspectorTab=cmd=="notes" ? 1:2;showInspector=true;buildInspector();layoutViews()
        case "outline":showOutline.toggle();if showOutline{select(selected)};refreshOutline();buildLibrary();layoutViews();window.makeFirstResponder(showOutline ? outline:canvas)
        case "search":showSearch.toggle();layoutViews();if showSearch{window.makeFirstResponder(searchField)}else{searchField.stringValue="";canvas.search="";canvas.needsDisplay=true}
        case "new":afterSaved{[weak self] in guard let self else{return};self.load(MindDocument.create());self.dirty=true;self.save();self.canvas.edit(self.selected)}
        case "open":let panel=NSOpenPanel();panel.canChooseDirectories=false;panel.allowsMultipleSelection=false;panel.beginSheetModal(for:window){[weak self] response in if response == .OK,let url=panel.url{self?.open(url)}}
        case "save":save()
        case "export":exportMenu()
        case "image":let panel=NSOpenPanel();panel.allowedContentTypes=[.jpeg,.png];panel.allowsMultipleSelection=false;panel.beginSheetModal(for:window){[weak self] response in if response == .OK{self?.insertImages(panel.urls)}}
        case "copyLink":NSPasteboard.general.clearContents();NSPasteboard.general.setString("branch://\(document.id)/\(selected)",forType:.string);saveLabel.stringValue="节点链接已复制"
        case "openLink":if let s=document.node(selected)?.text("link"),let url=URL(string:s){if url.scheme=="branch"{open(url)}else if ["https","http"].contains(url.scheme ?? ""){NSWorkspace.shared.open(url)}}
        case "help":message("快捷键","Tab：子节点 · Enter：同级节点 · 双击 / 轻按空格：编辑\n标题编辑时 Shift+Enter 换行，Esc 取消。\n空白处拖动：框选。Shift / ⌘：增选；点击节点可切换选中。\n空格按住拖动：平移画布。滚轮也可平移。\n拖动已选节点：移动所选子树。拖动单个分支到另一节点：改父级。⌥拖动：自由摆放。\n⌥↑ / ⌥↓：同级排序 · ⌘Z / ⇧⌘Z：撤销 / 重做\n⌘S：保存 · ⌘W：关闭 · 捏合或 ⌘滚轮缩放。\n双击关系线编辑标题，右键删除关系线。")
        case "mcp":let path=Bundle.main.resourceURL!.appendingPathComponent("scripts/mcp.py").path;let raw:[String:Any]=["mcpServers":["branch":["command":"/usr/bin/python3","args":[path]]]];let data=try? JSONSerialization.data(withJSONObject:raw,options:[.prettyPrinted,.sortedKeys]);let a=NSAlert();a.messageText="本地 MCP";a.informativeText="默认只读。args 加 --write 开启修改。\n工程目录：\(store.root.path)\n\n"+(data.flatMap{String(data:$0,encoding:.utf8)} ?? "");a.addButton(withTitle:"复制配置");a.addButton(withTitle:"关闭");if a.runModal() == .alertFirstButtonReturn,let data{NSPasteboard.general.clearContents();NSPasteboard.general.setString(String(data:data,encoding:.utf8)!,forType:.string)}
        case "recovery":let a=NSAlert();a.messageText="保存与恢复";a.informativeText="先导出当前工程副本，保留尚未保存的编辑。重新载入会放弃本次未保存修改。";a.addButton(withTitle:"导出副本");a.addButton(withTitle:"取消");a.addButton(withTitle:"重新载入");let result=a.runModal();if result == .alertFirstButtonReturn{export("branch")}else if result == .alertThirdButtonReturn{saveWork?.cancel();do{load(try store.read(document.id))}catch{alert(error)}}
        case "about":NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"枝图",.applicationVersion:"0.2.2 · 原生 macOS",.credits:NSAttributedString(string:"自己的想法，留在自己的电脑。")])
        default:break
        }
    }
    func navigate(_ key:UInt16,reorder:Bool){guard let n=document.node(selected) else{return};let siblings=document.children(n.parent),i=siblings.firstIndex{$0.id==n.id} ?? 0
        if reorder,[125,126].contains(key),let parent=n.parent{mutate{try $0.move(n.id,to:parent,index:max(0,i+(key==126 ? -1:1)))};return}
        if key==123,let parent=n.parent{select(parent)}else if key==124,let child=document.children(n.id).first{if n.flag("collapsed"){editNode(n.id,key:"collapsed",value:false)};select(child.id)}else if key==126,i>0{select(siblings[i-1].id)}else if key==125,i+1<siblings.count{select(siblings[i+1].id)}
    }
    func addConnection(from:String,to:String){mutate{$0.connections.append(["from":from,"to":to,"title":""])}}
    func editConnection(_ index:Int){guard document.connections.indices.contains(index) else{return};let a=NSAlert();a.messageText="关系线标题";a.addButton(withTitle:"确定");a.addButton(withTitle:"取消");let field=NSTextField(string:document.connections[index]["title"] as? String ?? "");field.frame=CGRect(x:0,y:0,width:300,height:26);a.accessoryView=field;if a.runModal() == .alertFirstButtonReturn{mutate{$0.connections[index]["title"]=field.stringValue}}}
    @objc func deleteConnectionMenu(_ sender:NSMenuItem){if document.connections.indices.contains(sender.tag){mutate{$0.connections.remove(at:sender.tag)}}}
    func controlTextDidChange(_ obj:Notification){if obj.object as? NSSearchField === searchField{canvas.search=searchField.stringValue;canvas.needsDisplay=true}}
    func message(_ title:String,_ text:String){let a=NSAlert();a.messageText=title;a.informativeText=text;a.addButton(withTitle:"确定");a.runModal()}
    func alert(_ error:Error){message("枝图",error.localizedDescription)}
}
