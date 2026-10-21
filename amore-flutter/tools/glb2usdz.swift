// glb2usdz.swift — GLB → USDZ（ModelIO 导入 → SceneKit 导出）
// CI 用法：swift glb2usdz.swift in.glb out.usdz
// 说明：新版 Xcode 已移除 usdzconvert，且命令行 swift 脚本下 MDLAsset 的
// rootNode/rootObject 便利访问在 SDK 变动中不可靠，这里统一走 MDLAsset.count/indexed
// 子项遍历（稳定 API）。
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
    guard let obj = asset.object(at: i) as? MDLObject else { continue }
    let node = SCNNode(mdlObject: obj)
    scene.rootNode.addChildNode(node)
    added += 1
}

guard added > 0 else {
    print("no objects imported")
    exit(2)
}
print("imported \(added) top-level objects")

let okWrite = scene.write(to: outURL, options: [:],
                          delegate: nil as SCNSceneExportDelegate?,
                          progressHandler: nil as SCNSceneExportProgressHandler?)
if okWrite {
    print("USDZ written: \(outURL.path)")
} else {
    print("write failed")
    exit(2)
}
