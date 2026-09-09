import AppKit

extension BranchController {
    func stack(in scroll:NSScrollView,width:CGFloat)->FormPanel {
        let panel=FormPanel(frame:CGRect(x:0,y:0,width:width,height:32));scroll.documentView=panel;return panel
    }
    func row(_ view:NSView,in stack:FormPanel,height:CGFloat=26){stack.append(view,height:height)}
    func buildLibrary(){
        guard showLibrary else{return};let stack=stack(in:libraryScroll,width:235)
        row(label("文档",size:15),in:stack)
        row(ActionButton("新建导图",symbol:"plus"){[weak self] in self?.command("new")},in:stack)
        row(ActionButton("打开 / 导入…"){[weak self] in self?.command("open")},in:stack)
        row(ActionButton(showOutline ? "切换到导图":"切换到大纲"){[weak self] in self?.command("outline")},in:stack)
        row(label("本机 · \(library.count) 份导图",size:11),in:stack)
        for entry in library {let b=ActionButton(entry.title){[weak self] in self?.showDocument(entry.id)};b.alignment = .left;b.lineBreakMode = .byTruncatingTail;b.contentTintColor=entry.id==document.id ? .controlAccentColor:.labelColor;row(b,in:stack,height:32)}
        row(ActionButton("本地连接 / MCP"){[weak self] in self?.command("mcp")},in:stack)
    }
    func buildInspector(){
        guard showInspector,let n=document.node(selected) else{return};let id=n.id,stack=stack(in:inspectorScroll,width:280)
        let tabs=NSStackView();tabs.orientation = .horizontal;tabs.distribution = .fillEqually
        for (i,title) in ["样式","备注","标签","画布"].enumerated(){let b=ActionButton(title){[weak self] in self?.commitEditing();self?.inspectorTab=i;self?.buildInspector()};if i==inspectorTab{b.contentTintColor = .controlAccentColor};tabs.addArrangedSubview(b)}
        row(tabs,in:stack,height:30)
        func field(_ title:String,_ key:String){row(label(title,size:11),in:stack,height:17);row(ActionField(n.text(key),placeholder:title){[weak self] value in self?.editNode(id,key:key,value:value)},in:stack)}
        func popup(_ title:String,_ key:String,_ names:[String],_ values:[String],_ current:String){row(label(title,size:11),in:stack,height:17);row(ActionPopup(names,selected:values.firstIndex(of:current) ?? 0){[weak self] index in self?.editNode(id,key:key,value:values[index])},in:stack)}
        switch inspectorTab {
        case 0:
            field("文字","title");popup("字体","fontFamily",["系统","衬线","等宽"],["system","serif","mono"],n.text("fontFamily"))
            popup("字号","fontSize",["12","14","16","18","20","24","28","32","40","48"],["12","14","16","18","20","24","28","32","40","48"],String(Int(n.fontSize)))
            popup("节点形状","shape",["下划线","圆角矩形","矩形","胶囊"],["line","rounded","rectangle","pill"],n.text("shape"))
            popup("分支","lineStyle",["曲线","直线","虚线"],["curve","straight","dashed"],n.text("lineStyle"))
            row(label("颜色",size:11),in:stack,height:17)
            let colors=NSStackView();colors.orientation = .horizontal;colors.distribution = .fillEqually
            for color in MindLayout.palette{let b=ActionButton("●"){[weak self] in self?.editNode(id,key:"color",value:color)};b.isBordered=false;b.contentTintColor=NSColor(hex:color);b.font = .systemFont(ofSize:22);colors.addArrangedSubview(b)}
            row(colors,in:stack,height:30);let well=ActionColor(NSColor(hex:n.text("color").isEmpty ? canvas.placements.first{$0.id==id}?.color ?? "#f49b51":n.text("color"))){[weak self] color in self?.editNode(id,key:"color",value:color.hex)};well.setAccessibilityLabel("自定义颜色");row(well,in:stack,height:28)
            row(ActionButton("删除分支"){[weak self] in self?.command("delete")},in:stack)
        case 1:
            row(label("备注",size:11),in:stack,height:17)
            let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;let text=NotesEditor(frame:CGRect(x:0,y:0,width:230,height:170));text.string=n.text("notes");text.font = .systemFont(ofSize:13);text.isRichText=false;text.isVerticallyResizable=true;text.autoresizingMask=[.width];text.textContainer?.widthTracksTextView=true;text.setAccessibilityLabel("节点备注");text.commit={[weak self] value in self?.editNode(id,key:"notes",value:value)};scroll.documentView=text;row(scroll,in:stack,height:180)
            row(ActionCheck("任务",value:n.flag("task")){[weak self] v in self?.editNode(id,key:"task",value:v)},in:stack)
            row(ActionCheck("已完成",value:n.flag("done")){[weak self] v in self?.editNode(id,key:"done",value:v)},in:stack)
            let ids=document.descendants(id),tasks=document.nodes.filter{ids.contains($0.id)&&$0.flag("task")};row(label("完成 \(tasks.filter{$0.flag("done")}.count) / \(tasks.count)",size:11),in:stack)
            field("链接","link");row(ActionButton("打开链接"){[weak self] in self?.command("openLink")},in:stack);row(ActionButton("复制此节点链接"){[weak self] in self?.command("copyLink")},in:stack)
            row(ActionButton(n.text("image").isEmpty ? "插入图片":"替换图片"){[weak self] in self?.command("image")},in:stack)
            if !n.text("image").isEmpty {popup("图片显示高度","imageSize",["60","100","150","200","240"],["60","100","150","200","240"],String(Int(n.imageHeight)));row(ActionButton("移除图片"){[weak self] in self?.editNode(id,key:"image",value:nil)},in:stack)}
        case 2:
            field("标签（空格或逗号分隔）","tags");row(ActionButton("搜索标签"){[weak self] in self?.command("search")},in:stack)
            row(label("搜索会高亮匹配标题或标签的节点。",size:11),in:stack,height:40)
        default:
            row(label("主题",size:11),in:stack,height:17);row(ActionPopup(["深色","浅色"],selected:document.theme=="light" ? 1:0){[weak self] i in self?.mutate{$0.raw["theme"]=i==1 ? "light":"dark"}},in:stack)
            row(label("布局",size:11),in:stack,height:17);let layouts=["horizontal","compact","vertical"];row(ActionPopup(["水平","紧凑","纵向"],selected:layouts.firstIndex(of:document.layout) ?? 0){[weak self] i in self?.mutate{d in d.raw["layout"]=layouts[i];for n in d.nodes{d.set(n.id,"position",nil)}};self?.canvas.fit()},in:stack)
            row(ActionButton("重新自动布局"){[weak self] in self?.command("reset")},in:stack);row(ActionButton("适配全部内容"){[weak self] in self?.canvas.fit()},in:stack)
            row(ActionButton("导图 / 大纲"){[weak self] in self?.command("outline")},in:stack)
        }
    }
    @objc func editOutline(){
        if let id=outline.item(atRow:outline.clickedRow) as? String{select(id);beginOutlineEdit(id)}
    }
    func beginOutlineEdit(_ id:String){
        guard let item=outlineNodes[id] else{return};let row=outline.row(forItem:item);guard row>=0 else{return}
        outline.scrollRowToVisible(row)
        if let field=outline.view(atColumn:0,row:row,makeIfNecessary:true) as? NSTextField{window.makeFirstResponder(field);field.selectText(nil)}
    }
    var outlineRoots:[MindNode]{focusID.flatMap{document.node($0)}.map{[$0]} ?? document.roots}
    func refreshOutline(){
        guard showOutline else{return}
        outlineNodes=Dictionary(uniqueKeysWithValues:document.nodes.map{($0.id,$0.id as NSString)});outline.reloadData()
        func expand(_ n:MindNode){if !n.flag("collapsed"),let item=outlineNodes[n.id]{outline.expandItem(item);for c in document.children(n.id){expand(c)}}}
        for root in outlineRoots{expand(root)}
        if let item=outlineNodes[selected]{let row=outline.row(forItem:item);if row>=0{outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}}
    }
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{guard let id=item as? String else{return outlineRoots.count};return document.children(id).count}
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{let id=(item as? String).map{document.children($0)[index].id} ?? outlineRoots[index].id;return outlineNodes[id] ?? id as NSString}
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{!document.children(item as? String ?? "").isEmpty}
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{guard let id=item as? String,let n=document.node(id) else{return nil};let field=ActionField(n.title,placeholder:"大纲节点"){[weak self] value in self?.editNode(id,key:"title",value:value)};field.isBordered=false;field.drawsBackground=false;return field}
    func outlineViewSelectionDidChange(_ notification:Notification){guard !refreshing,let id=outline.item(atRow:outline.selectedRow) as? String,selected != id else{return};select(id)}
    func outlineViewItemDidCollapse(_ notification:Notification){guard !refreshing,let id=notification.userInfo?["NSObject"] as? String,document.node(id)?.flag("collapsed")==false else{return};editNode(id,key:"collapsed",value:true)}
    func outlineViewItemDidExpand(_ notification:Notification){guard !refreshing,let id=notification.userInfo?["NSObject"] as? String,document.node(id)?.flag("collapsed")==true else{return};editNode(id,key:"collapsed",value:false)}
}
