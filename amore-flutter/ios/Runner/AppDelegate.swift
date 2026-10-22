// Amore — AppDelegate：注册 Doll 3D SceneKit PlatformView
import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        var flutterVC: FlutterViewController? = window?.rootViewController as? FlutterViewController
        if flutterVC == nil {
            // 兜底：遍历找 FlutterViewController
            if let root = window?.rootViewController {
                root.children.forEach { vc in
                    if vc is FlutterViewController { flutterVC = vc as? FlutterViewController }
                }
            }
        }
        if let controller = flutterVC {
            let factory = DollSceneFactory(messenger: controller.binaryMessenger)
            registrar(forPlugin: "DollScenePlugin")?.register(factory, withId: "doll_scene")
            NSLog("[DollScene] factory registered withId=doll_scene")
        } else {
            NSLog("[DollScene] !! FlutterViewController not found - factory NOT registered")
        }
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
