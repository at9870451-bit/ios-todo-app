// glb2usdz.swift — GLB → USDZ（ModelIO 导入 → SceneKit 导出）
// CI 用法：swift glb2usdz.swift in.glb out.usdz
// 说明：新版 Xcode 已移除 usdzconvert。这里用稳定 API 组合：
//   MDLAsset(indexed children) → SCNNode(mdlObject:) → scene.write(...)
// 若 SCNSceneExportDelegate 签名在目标 SDK 变化，见底部注释。
import Foundation
import ModelIO
import SceneKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: glb2usdz in.glb out.usdz")
    exit(1)
}
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

let asset = MDLAsset(url: inURL)
asset.loadTextures()

let scene = SCNScene()
var added = 0

// 遍历 asset 顶层对象（MDLObject 集合下标 API，稳定）
for i in 0..<asset.count(objectAt: 0) {
    let obj: MDLObject = asset.object(at: i)
    let node = SCNNode(mdlObject: obj)
    scene.rootNode.addChildNode(node)
    added += 1
}

guard added > 0 else {
    print("no objects imported")
    exit(2)
}
print("imported \(added) top-level objects")

// 新 SDK 的 write 返回 Bool（不抛错）；delegate/progressHandler 需显式类型
let exporter = scene
let ok: Bool = exporter.write(
    to: outURL,
    options: [:] as [String: Any],
    delegate: nil as (any SCNSceneExportDelegate)?,
    progressHandler: nil as ((Float, (any Error)?, UnsafeMutablePointer<ObjCBool>) -> Void)?
)
if ok {
    print("USDZ written: \(outURL.path)")
} else {
    print("write failed")
    exit(2)
}
