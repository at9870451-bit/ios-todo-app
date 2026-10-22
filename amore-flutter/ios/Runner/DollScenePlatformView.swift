// Amore — Doll Scene PlatformView：Flutter ↔ SceneKit 桥
// viewId: "doll_scene"；channel: amore/doll_scene
import Flutter
import SceneKit
import UIKit

final class DollSceneFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let controller = DollSceneController3D()   // 共享一个场景（单玩偶页实例）
    private(set) var createCalls = 0
    var registeredAt = Date()

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
        NSLog("[DollScene] factory init ok")
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        createCalls += 1
        NSLog("[DollScene] factory create #\(createCalls) frame=\(frame)")
        let v = DollScenePlatformView(frame: frame, viewId: viewId,
                                      args: args, messenger: messenger, controller: controller)
        v.factory = self
        return v
    }

    func createArgs(for viewId: Int64) -> Any? { nil }
}

final class DollScenePlatformView: NSObject, FlutterPlatformView {
    private let scnView: SCNView
    private let controller: DollSceneController3D
    private let channel: FlutterMethodChannel
    weak var factory: DollSceneFactory?

    init(frame: CGRect, viewId: Int64, args: Any?,
         messenger: FlutterBinaryMessenger, controller: DollSceneController3D,
         factory: DollSceneFactory? = nil) {
        self.factory = factory
        self.controller = controller
        scnView = SCNView()
        scnView.scene = controller.scene
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = false
        scnView.backgroundColor = .clear
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        channel = FlutterMethodChannel(name: "amore/doll_scene", binaryMessenger: messenger)

        super.init()

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }

        // 手势：旋转 / 缩放
        scnView.addGestureRecognizer(UIPanGestureRecognizer(
            target: self, action: #selector(onPan(_:))))
        scnView.addGestureRecognizer(UIPinchGestureRecognizer(
            target: self, action: #selector(onPinch(_:))))
    }

    func view() -> UIView { scnView }

    // MARK: MethodChannel 处理

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "setCharacter":
            let gender = args["gender"] as? String ?? "female"
            let skin = args["skin"] as? String ?? "#F3C6A5"
            let hs = (args["heightScale"] as? NSNumber)?.doubleValue ?? 1.0
            controller.setCharacter(gender: gender, skin: skin, heightScale: hs)
            result(true)
        case "updateSlots":
            if let slots = args["slots"] as? [String: [String: String]] {
                controller.updateSlots(slots)
            }
            result(true)
        case "applyPose":
            let pose = DollPose3D(rawValue: args["pose"] as? String ?? "standing") ?? .standing
            controller.applyPose(pose)
            result(true)
        case "face":
            controller.face(args["label"] as? String ?? "正面")
            result(true)
        case "resetView":
            controller.resetView()
            result(true)
        case "loadSkinned":
            let name = args["name"] as? String ?? "CesiumMan"
            result(controller.loadSkinned(named: name))
        case "defaultSkinned":
            result(controller.defaultSkinned)
        case "diagnostics":
            let dae = Bundle.main.url(forResource: "CesiumMan", withExtension: "dae") != nil
            var bodyInfo = "none"
            if let body = controller.dollRoot.childNode(withName: "body", recursively: false) {
                bodyInfo = "children=\(body.childNodes.count)"
            }
            result([
                "createCalls": factory?.createCalls ?? -1,
                "body": bodyInfo,
                "skinnedLoaded": controller.isSkinnedLoaded,
                "bundleDae": dae,
                "scnViewFrame": NSStringFromRect(scnView.frame),
                "sceneRoots": controller.scene.rootNode.childNodes.count,
            ])
        case "unloadSkinned":
            controller.unloadSkinned()
            result(true)
        case "snapshot":
            DispatchQueue.main.async {
                let img = self.scnView.snapshot()
                result(img.pngData())
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: 手势

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: scnView)
        controller.orbit(dx: Float(t.x), dy: Float(t.y))
        g.setTranslation(.zero, in: scnView)
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            controller.zoom(Float(g.scale))
            g.scale = 1
        }
    }
}
