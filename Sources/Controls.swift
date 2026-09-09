import AppKit
final class ActionButton:NSButton {
    var handler:(()->Void)?
    init(_ title:String,symbol:String?=nil,action:@escaping ()->Void){super.init(frame:.zero);self.title=title;handler=action;target=self;self.action=#selector(run);bezelStyle = .rounded;if let symbol{image=NSImage(systemSymbolName:symbol,accessibilityDescription:title);imagePosition = .imageOnly;isBordered=false;contentTintColor = .secondaryLabelColor};toolTip=title;setAccessibilityLabel(title)}
    required init?(coder:NSCoder){fatalError()}
    @objc func run(){handler?()}
}
final class ActionField:NSTextField,NSTextFieldDelegate {
    var commit:((String)->Void)?
    init(_ value:String,placeholder:String="",commit:@escaping (String)->Void){super.init(frame:.zero);stringValue=value;placeholderString=placeholder;self.commit=commit;delegate=self;font = .systemFont(ofSize:13);setAccessibilityLabel(placeholder)}
    required init?(coder:NSCoder){fatalError()}
    func controlTextDidEndEditing(_ obj:Notification){commit?(stringValue)}
}
final class ActionPopup:NSPopUpButton {
    var handler:((Int)->Void)?
    init(_ items:[String],selected:Int,action:@escaping(Int)->Void){super.init(frame:.zero,pullsDown:false);addItems(withTitles:items);selectItem(at:selected);handler=action;target=self;self.action=#selector(run)}
    required init?(coder:NSCoder){fatalError()}
    @objc func run(){handler?(indexOfSelectedItem)}
}
final class ActionCheck:NSButton {
    var handler:((Bool)->Void)?
    init(_ title:String,value:Bool,action:@escaping(Bool)->Void){super.init(frame:.zero);setButtonType(.switch);self.title=title;state=value ? .on:.off;handler=action;target=self;self.action=#selector(run)}
    required init?(coder:NSCoder){fatalError()}
    @objc func run(){handler?(state == .on)}
}
final class ActionColor:NSColorWell {
    var handler:((NSColor)->Void)?
    init(_ color:NSColor,action:@escaping(NSColor)->Void){super.init(frame:.zero);self.color=color;handler=action;target=self;self.action=#selector(run)}
    required init?(coder:NSCoder){fatalError()}
    @objc func run(){handler?(color)}
}
final class NotesEditor:NSTextView {
    var commit:((String)->Void)?
    override func resignFirstResponder()->Bool{let ok=super.resignFirstResponder();if ok{commit?(string)};return ok}
}
class FlippedView:NSView {override var isFlipped:Bool{true}}
final class RootView:FlippedView {var onLayout:(()->Void)?;override func layout(){super.layout();onLayout?()}}
final class HeaderView:FlippedView {
    override func draw(_ rect:NSRect){NSColor.windowBackgroundColor.setFill();bounds.fill();NSColor.separatorColor.setFill();CGRect(x:0,y:bounds.height-1,width:bounds.width,height:1).fill()}
    override func mouseDown(with event:NSEvent){if event.clickCount==2{window?.zoom(nil)}else{window?.performDrag(with:event)}}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
}
func label(_ title:String,size:CGFloat=12)->NSTextField{let t=NSTextField(labelWithString:title);t.font = .systemFont(ofSize:size);t.textColor = .secondaryLabelColor;return t}

final class FormPanel:FlippedView {
    private var nextY:CGFloat=16
    func append(_ view:NSView,height:CGFloat){
        view.translatesAutoresizingMaskIntoConstraints=true
        view.frame=CGRect(x:16,y:nextY,width:bounds.width-32,height:height)
        addSubview(view);nextY+=height+8;setFrameSize(CGSize(width:frame.width,height:nextY+8))
    }
}

final class NativeOutline:NSOutlineView {
    weak var controller:BranchController?
    override func keyDown(with event:NSEvent){
        if !event.modifierFlags.contains(.command){
            switch event.keyCode {
            case 36,49:controller?.command("edit");return
            case 48:controller?.command("child");return
            case 51,117:controller?.command("delete");return
            default:break
            }
        }
        super.keyDown(with:event)
    }
}
