import AppKit

final class App:NSObject,NSApplicationDelegate {
    let controller=BranchController()
    func applicationDidFinishLaunching(_ notification:Notification){NSApp.setActivationPolicy(.regular);controller.start()}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply{controller.terminate()}
    func application(_ sender:NSApplication,openFiles filenames:[String]){for name in filenames{controller.open(URL(fileURLWithPath:name))};sender.reply(toOpenOrPrint:.success)}
    func application(_ application:NSApplication,open urls:[URL]){for url in urls{controller.open(url)}}
}
if CommandLine.arguments.count==4 {
    do {
        let input=URL(fileURLWithPath:CommandLine.arguments[2]),output=URL(fileURLWithPath:CommandLine.arguments[3])
        if CommandLine.arguments[1]=="--convert-image"{try jpegFile(input,output);exit(0)}
        if CommandLine.arguments[1]=="--render-pdf"{try makePDF(Data(contentsOf:input)).write(to:output,options:.atomic);exit(0)}
    }catch{fputs(error.localizedDescription+"\n",stderr);exit(1)}
}
let app=NSApplication.shared
let delegate=App();app.delegate=delegate
app.run()
