// glb2usdz.swift — GLB → USDZ（ModelIO 导入 → SceneKit 导出）
// CI 用法：swift glb2usdz.swift in.glb out.usdz
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
let root = SCNNode(mdlObject: asset.rootObject)
scene.rootNode.addChildNode(root)
guard scene.rootNode.childNodes.isEmpty == false else {
    print("empty scene")
    exit(2)
}

let okWrite = scene.write(to: outURL, options: [:],
                          delegate: nil as SCNSceneExportDelegate?,
                          progressHandler: nil as SCNSceneExportProgressHandler?)
if okWrite {
    print("USDZ written: \(outURL.path)")
} else {
    print("write failed")
    exit(2)
}
