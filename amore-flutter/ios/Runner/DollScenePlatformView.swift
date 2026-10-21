// Amore — Doll Scene PlatformView：Flutter ↔ SceneKit 桥
// viewId: "doll_scene"；channel: amore/doll_scene
import Flutter
import SceneKit
import UIKit

final class DollSceneFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let controller = DollSceneController3D()   // 共享一个场景（单玩偶页实例）

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier: Int64,
                arguments args: Any?, binaryMessenger: FlutterBinaryMessenger) -> FlutterPlatformView {
        DollScenePlatformView(frame: frame, viewId: viewIdentifier,
                              args: args, messenger: messenger, controller: controller)
    }

    func createArgs(for viewId: Int64) -> Any? { nil }
}

final class DollScenePlatformView: NSObject, FlutterPlatformView {
    private let scnView: SCNView
    private let controller: DollSceneController3D
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, args: Any?,
         messenger: FlutterBinaryMessenger, controller: DollSceneController3D) {
        controller_ = controller
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

    private let controller_: DollSceneController3D

    func view() -> UIView { scnView }

    // MARK: MethodChannel 处理

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "setCharacter":
            let gender = args["gender"] as? String ?? "female"
            let skin = args["skin"] as? String ?? "#F3C6A5"
            let hs = (args["heightScale"] as? NSNumber)?.doubleValue ?? 1.0
            controller_.setCharacter(gender: gender, skin: skin, heightScale: hs)
            result(true)
        case "updateSlots":
            if let slots = args["slots"] as? [String: [String: String]] {
                controller_.updateSlots(slots)
            }
            result(true)
        case "applyPose":
            let pose = DollPose3D(rawValue: args["pose"] as? String ?? "standing") ?? .standing
            controller_.applyPose(pose)
            result(true)
        case "face":
            controller_.face(args["label"] as? String ?? "正面")
            result(true)
        case "resetView":
            controller_.resetView()
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
        controller_.orbit(dx: Float(t.x), dy: Float(t.y))
        g.setTranslation(.zero, in: scnView)
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            controller_.zoom(Float(g.scale))
            g.scale = 1
        }
    }
}
