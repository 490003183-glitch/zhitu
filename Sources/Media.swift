import AppKit
import ImageIO
import UniformTypeIdentifiers

func makePDF(_ data:Data) throws -> Data {
    guard let image=NSImage(data:data),let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else{throw NSError(domain:"图片无效",code:1)}
    let result=NSMutableData();guard let consumer=CGDataConsumer(data:result) else{throw NSError(domain:"PDF 创建失败",code:1)}
    let scale=min(1,14400/CGFloat(max(cg.width,cg.height)));var box=CGRect(x:0,y:0,width:CGFloat(cg.width)*scale,height:CGFloat(cg.height)*scale)
    guard let ctx=CGContext(consumer:consumer,mediaBox:&box,nil) else{throw NSError(domain:"PDF 创建失败",code:1)}
    ctx.beginPDFPage(nil);ctx.draw(cg,in:box);ctx.endPDFPage();ctx.closePDF();return result as Data
}
func jpegFile(_ input:URL,_ output:URL) throws {
    let data=try Data(contentsOf:input)
    guard let source=CGImageSourceCreateWithData(data as CFData,nil),let type=CGImageSourceGetType(source) as String?,["public.jpeg","public.png"].contains(type),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{throw NSError(domain:"仅接受有效 JPG 或 PNG",code:1)}
    guard image.width*image.height<=80000000 else{throw NSError(domain:"图片像素过大",code:1)}
    if type=="public.jpeg"{try data.write(to:output,options:.atomic);return}
    let space=CGColorSpaceCreateDeviceRGB();guard let ctx=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else{throw NSError(domain:"转换失败",code:1)}
    ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:image.width,height:image.height));ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    let result=NSMutableData();guard let flattened=ctx.makeImage(),let dest=CGImageDestinationCreateWithData(result,"public.jpeg" as CFString,1,nil) else{throw NSError(domain:"转换失败",code:1)}
    CGImageDestinationAddImage(dest,flattened,[kCGImageDestinationLossyCompressionQuality:0.94] as CFDictionary);guard CGImageDestinationFinalize(dest) else{throw NSError(domain:"转换失败",code:1)};try (result as Data).write(to:output,options:.atomic)
}
