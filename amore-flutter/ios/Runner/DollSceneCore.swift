// Amore — Doll Scene 3D 核心（纯 UIKit，从 Doll Studio 3D 移植）
// 程序化模块化玩偶 + 参数化服装 + 相机轨道。由 DollScenePlatformView 经 MethodChannel 驱动。
import SceneKit
import UIKit

enum DollPose3D: String {
    case standing, relaxed, presentation
}

final class DollSceneController3D: NSObject, ObservableObject {
    let scene = SCNScene()
    let yawNode = SCNNode()
    let pitchNode = SCNNode()
    let cameraNode = SCNNode()
    let dollRoot = SCNNode()

    private(set) var gender = "female"
    private(set) var skin = "#F3C6A5"
    private(set) var heightScale = 1.0
    private(set) var pose: DollPose3D = .standing

    private let baseDistance: Float = 4.6

    override init() {
        super.init()
        setupScene()
    }

    private func setupScene() {
        scene.background.contents = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)

        scene.rootNode.addChildNode(yawNode)
        yawNode.addChildNode(pitchNode)
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.1
        camera.zFar = 50
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.05, baseDistance)
        cameraNode.look(at: SCNVector3(0, 1.0, 0))
        pitchNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 620
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 850
        key.light?.castsShadow = true
        key.light?.shadowRadius = 9
        key.light?.shadowColor = UIColor(white: 0.35, alpha: 0.55)
        key.eulerAngles = SCNVector3(-0.9, 0.5, 0)
        key.position = SCNVector3(2.5, 5, 3)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 320
        fill.eulerAngles = SCNVector3(-0.4, -1.2, 0)
        fill.position = SCNVector3(-3, 3, -2)
        scene.rootNode.addChildNode(fill)

        let ground = SCNFloor()
        ground.reflectivity = 0
        let gm = SCNMaterial()
        gm.lightingModel = .lambert
        gm.diffuse.contents = UIColor(red: 0.945, green: 0.945, blue: 0.955, alpha: 1)
        ground.materials = [gm]
        scene.rootNode.addChildNode(SCNNode(geometry: ground))

        scene.rootNode.addChildNode(dollRoot)
    }

    // MARK: 玩偶重建

    func setCharacter(gender: String, skin: String, heightScale: Double) {
        let structural = gender != self.gender || skin != self.skin
        self.gender = gender
        self.skin = skin
        self.heightScale = heightScale
        if structural {
            dollRoot.childNodes.forEach { $0.removeFromParentNode() }
            let doll = DollBuilder3D.buildBody(gender: gender, skin: skin, heightScale: heightScale)
            doll.name = "body"
            dollRoot.addChildNode(doll)
            rebuildClothLayer()
            applyPose(pose)
        }
    }

    // MARK: 真 3D 骨骼模型（SCNSkinner）

    private var skinnedLoaded = false
    private var skinnedNode: SCNNode?

    /// 加载带骨骼的人物 USDZ（bundle 内置或远程），播放其内置动画（如行走）
    @discardableResult
    func loadSkinned(named: String = "CesiumMan") -> Bool {
        unloadSkinned()
        guard let url = Bundle.main.url(forResource: named, withExtension: "usdz") else {
            return false
        }
        guard let src = SCNSceneSource(url: url, options: nil),
              let sceneObj = src.scene() else { return false }

        let root = sceneObj.rootNode.clone()

        // 收集内置动画（.identifier 为 key）并在根节点循环播放
        var animationKeys: [String] = []
        src.identifiersOfEntries(withClass: CAAnimation.self).forEach { key in
            if let anim = src.entry(withIdentifier: key) as? CAAnimation {
                anim.repeatCount = Float.greatestFiniteMagnitude
                animationKeys.append(key)
                root.addAnimation(anim, forKey: key)
            }
        }

        // 归一化：缩放到 ~1.6m 高度并落地
        let (minB, maxB) = root.boundingBox
        let height = max(0.001, Float(maxB.y - minB.y))
        let scale = 1.6 / height
        root.scale = SCNVector3(scale, scale, scale)
        root.position = SCNVector3(0, Float(-minB.y * scale), 0)

        let wrapper = SCNNode()
        wrapper.addChildNode(root)
        wrapper.name = "skinned"
        dollRoot.addChildNode(wrapper)
        skinnedNode = wrapper
        skinnedLoaded = true
        _ = animationKeys.count
        return true
    }

    func unloadSkinned() {
        skinnedNode?.removeFromParentNode()
        skinnedNode = nil
        skinnedLoaded = false
        // 恢复程序化身体
        setCharacter(gender: gender, skin: skin, heightScale: heightScale)
    }

    var isSkinnedLoaded: Bool { skinnedLoaded }

    // MARK: 换装（slots: [category: ["kind": String, "color": String]]）

    func updateSlots(_ slots: [String: [String: String]]) {
        currentSlots = slots
        rebuildClothLayer()
    }

    private var currentSlots: [String: [String: String]] = [:]

    private func rebuildClothLayer() {
        guard let body = dollRoot.childNode(withName: "body", recursively: false) else { return }
        body.childNode(withName: "cloth", recursively: false)?.removeFromParentNode()
        let layer = SCNNode()
        layer.name = "cloth"
        for (category, slot) in currentSlots.sorted(by: { $0.key < $1.key }) {
            let kind = slot["kind"] ?? ""
            let hex = slot["color"] ?? "#888888"
            let node = DollBuilder3D.build(kind: kind, hex: hex, body: body)
            node.name = "cloth.\(category)"
            layer.addChildNode(node)
        }
        body.addChildNode(layer)
    }

    // MARK: 姿势

    func applyPose(_ pose: DollPose3D) {
        self.pose = pose
        guard let body = dollRoot.childNode(withName: "body", recursively: false) else { return }
        let lArm = body.childNode(withName: "pivot.armL", recursively: true)
        let rArm = body.childNode(withName: "pivot.armR", recursively: true)
        let angle: Float
        switch pose {
        case .standing: angle = 0.0
        case .relaxed: angle = 0.14
        case .presentation: angle = 0.5
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        lArm?.eulerAngles = SCNVector3(0, 0, -angle)
        rArm?.eulerAngles = SCNVector3(0, 0, angle)
        SCNTransaction.commit()
    }

    // MARK: 视角

    func resetView() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        yawNode.eulerAngles.y = 0
        pitchNode.eulerAngles.x = 0
        cameraNode.position.z = baseDistance
        SCNTransaction.commit()
    }

    func face(_ label: String) {
        let yaw: Float
        switch label {
        case "正面": yaw = 0
        case "侧面": yaw = Float.pi / 2
        case "背面": yaw = Float.pi
        default: yaw = 0
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        yawNode.eulerAngles.y = yaw
        pitchNode.eulerAngles.x = 0
        SCNTransaction.commit()
    }

    func orbit(dx: Float, dy: Float) {
        yawNode.eulerAngles.y -= dx * 0.008
        pitchNode.eulerAngles.x = max(-0.5, min(0.5, pitchNode.eulerAngles.x - dy * 0.005))
    }

    func zoom(_ factor: Float) {
        let z = cameraNode.position.z * (1 / factor)
        cameraNode.position.z = max(2.6, min(7.0, z))
    }

    func snapshot() -> Data? {
        nil // 由 platform view 持 SCNView 实现
    }
}

// MARK: - 构建器（程序化模型；usdz 分支走 SCNReferenceNode）

enum DollBuilder3D {

    private static let legLen: CGFloat = 0.92
    private static var headY: CGFloat { legLen + 0.18 + 0.9 + 0.14 }

    static func buildBody(gender: String, skin: String, heightScale: Double) -> SCNNode {
        let (sr, sg, sb) = colorFromHex(skin)
        let skinColor = UIColor(red: CGFloat(sr), green: CGFloat(sg), blue: CGFloat(sb), alpha: 1)

        var shoulder: CGFloat = 1.0
        var hipWidth: CGFloat = 1.0
        var torsoH: CGFloat = 0.92
        switch gender {
        case "male": shoulder = 1.16; hipWidth = 0.94; torsoH = 0.96
        case "female": shoulder = 0.92; hipWidth = 1.12; torsoH = 0.9
        default: shoulder = 1.02; hipWidth = 1.02; torsoH = 0.93
        }

        func mat(_ color: UIColor, rough: CGFloat = 0.75) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color
            m.roughness.contents = rough
            m.metalness.contents = 0.0
            return m
        }

        let root = SCNNode()
        root.name = "body"

        let legGeo = SCNCapsule(capRadius: 0.085, height: legLen)
        legGeo.materials = [mat(skinColor)]
        for (name, x) in [("legL", CGFloat(-0.11)), ("legR", CGFloat(0.11))] {
            let leg = SCNNode(geometry: legGeo)
            leg.position = SCNVector3(Float(x * hipWidth), Float(legLen / 2 + 0.02), 0)
            leg.name = name
            root.addChildNode(leg)
            let foot = SCNNode(geometry: SCNBox(width: 0.13, height: 0.07, length: 0.22, chamferRadius: 0.03))
            foot.geometry?.materials = [mat(skinColor)]
            foot.position = SCNVector3(Float(x * hipWidth), 0.035, 0.045)
            root.addChildNode(foot)
        }

        let pelvis = SCNNode(geometry: SCNBox(width: 0.30 * hipWidth, height: 0.18, length: 0.16, chamferRadius: 0.06))
        pelvis.geometry?.materials = [mat(skinColor)]
        pelvis.position = SCNVector3(0, Float(legLen + 0.06), 0)
        root.addChildNode(pelvis)

        let torsoGeo = SCNCapsule(capRadius: 0.13, height: torsoH)
        torsoGeo.materials = [mat(skinColor)]
        let torso = SCNNode(geometry: torsoGeo)
        torso.position = SCNVector3(0, Float(legLen + 0.18 + torsoH / 2), 0)
        torso.scale = SCNVector3(Float(shoulder), 1, 1)
        root.addChildNode(torso)

        let neck = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.08))
        neck.geometry?.materials = [mat(skinColor)]
        neck.position = SCNVector3(0, Float(legLen + 0.18 + torsoH + 0.02), 0)
        root.addChildNode(neck)

        let head = SCNNode(geometry: SCNSphere(radius: 0.155))
        head.geometry?.materials = [mat(skinColor, rough: 0.6)]
        head.position = SCNVector3(0, Float(legLen + 0.18 + torsoH + 0.14), 0)
        head.name = "head"
        root.addChildNode(head)

        let armLen: CGFloat = 0.62
        let armGeo = SCNCapsule(capRadius: 0.055, height: armLen)
        armGeo.materials = [mat(skinColor)]
        for pivotName in ["pivot.armL", "pivot.armR"] {
            let sign: Float = pivotName.hasSuffix("L") ? -1 : 1
            let pivot = SCNNode()
            pivot.position = SCNVector3(sign * Float(0.145 * shoulder), Float(legLen + 0.18 + torsoH - 0.06), 0)
            pivot.name = pivotName
            let arm = SCNNode(geometry: armGeo)
            arm.position = SCNVector3(0, Float(-armLen / 2), 0)
            pivot.addChildNode(arm)
            root.addChildNode(pivot)
        }

        root.scale = SCNVector3(1, Float(heightScale), 1)
        return root
    }

    static func build(kind: String, hex: String, body: SCNNode) -> SCNNode {
        if kind == "usdz" {
            return SCNNode() // usdz 载入由 platform view 层按 url 处理（预留）
        }
        let (r, g, b) = colorFromHex(hex)
        let color = UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
        return build(kind: kind, color: color, body: body)
    }

    static func build(kind: String, color: UIColor, body: SCNNode) -> SCNNode {
        let node = SCNNode()
        let m = mat(color)
        let md = mat(color.darkened(0.25))

        switch kind {
        case "tee", "shirt", "hoodie", "sweater", "jacket", "coat":
            let h: CGFloat = kind == "coat" ? 0.78 : (kind == "tee" ? 0.42 : 0.58)
            let botR: CGFloat = kind == "coat" ? 0.21 : 0.185
            let tube = SCNTube(innerRadius: botR - 0.015, outerRadius: botR, height: h)
            tube.materials = [m]
            let shell = SCNNode(geometry: tube)
            shell.position = SCNVector3(0, Float(legLen + 0.18 + h / 2), 0)
            node.addChildNode(shell)
            if kind != "tee" {
                for side in ["L", "R"] {
                    guard let pivot = body.childNode(withName: "pivot.arm\(side)", recursively: true) else { continue }
                    let sleeveLen: CGFloat = (kind == "hoodie" || kind == "coat") ? 0.5 : 0.3
                    let sleeve = SCNTube(innerRadius: 0.058, outerRadius: 0.072, height: sleeveLen)
                    sleeve.materials = [m]
                    let sn = SCNNode(geometry: sleeve)
                    sn.position = SCNVector3(0, Float(-(0.04 + sleeveLen / 2)), 0)
                    pivot.addChildNode(sn)
                }
            }
            if kind == "hoodie" {
                let hood = SCNTorus(ringRadius: 0.145, pipeRadius: 0.032)
                hood.materials = [md]
                let hn = SCNNode(geometry: hood)
                hn.position = SCNVector3(0, Float(legLen + 0.18 + h - 0.02), -0.06)
                hn.eulerAngles.x = 1.2
                node.addChildNode(hn)
            }
            if kind == "coat" {
                let lapel = SCNNode(geometry: SCNBox(width: 0.1, height: 0.3, length: 0.02, chamferRadius: 0.01))
                lapel.geometry?.materials = [md]
                lapel.position = SCNVector3(0, Float(legLen + 0.18 + h - 0.18), 0.17)
                node.addChildNode(lapel)
            }

        case "pants", "shorts":
            let hipY = legLen + 0.06
            let hipH: CGFloat = kind == "shorts" ? 0.26 : 0.34
            let hip = SCNTube(innerRadius: 0.145, outerRadius: 0.165, height: hipH)
            hip.materials = [m]
            let hn = SCNNode(geometry: hip)
            hn.position = SCNVector3(0, Float(hipY - (kind == "shorts" ? 0.03 : 0.1)), 0)
            node.addChildNode(hn)
            if kind == "pants" {
                for (name, x) in [("legL", CGFloat(-0.11)), ("legR", CGFloat(0.11))] {
                    let pant = SCNTube(innerRadius: 0.088, outerRadius: 0.102, height: 0.62)
                    pant.materials = [m]
                    let pn = SCNNode(geometry: pant)
                    pn.position = SCNVector3(Float(x), Float(legLen - 0.31 + 0.02), 0)
                    node.addChildNode(pn)
                }
            }
        case "skirt", "longskirt":
            let len: CGFloat = kind == "skirt" ? 0.36 : 0.68
            let cone = SCNCone(topRadius: 0.15, bottomRadius: kind == "skirt" ? 0.26 : 0.3, height: len)
            cone.materials = [m]
            let cn = SCNNode(geometry: cone)
            cn.position = SCNVector3(0, Float(legLen + 0.06 - len / 2 + 0.08), 0)
            node.addChildNode(cn)

        case "scarf", "scarflong", "scarfneck":
            let ring = SCNTorus(ringRadius: 0.105, pipeRadius: kind == "scarfneck" ? 0.03 : 0.042)
            ring.materials = [m]
            let rn = SCNNode(geometry: ring)
            rn.position = SCNVector3(0, Float(legLen + 0.18 + 0.9 - 0.02), 0)
            rn.eulerAngles.x = .pi / 2
            node.addChildNode(rn)
            if kind == "scarflong" {
                let tail = SCNNode(geometry: SCNBox(width: 0.08, height: 0.34, length: 0.03, chamferRadius: 0.012))
                tail.geometry?.materials = [m]
                tail.position = SCNVector3(0.05, Float(legLen + 0.18 + 0.9 - 0.22), 0.11)
                node.addChildNode(tail)
            }

        case "cap":
            let crown = SCNNode(geometry: SCNSphere(radius: 0.148))
            crown.geometry?.materials = [m]
            crown.position = SCNVector3(0, Float(headY + 0.035), 0)
            crown.scale = SCNVector3(1, 0.72, 1)
            node.addChildNode(crown)
            let brim = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 0.014))
            brim.geometry?.materials = [md]
            brim.position = SCNVector3(0, Float(headY + 0.028), 0.14)
            brim.eulerAngles.x = 0.12
            node.addChildNode(brim)
        case "beanie":
            let crown = SCNNode(geometry: SCNSphere(radius: 0.152))
            crown.geometry?.materials = [m]
            crown.position = SCNVector3(0, Float(headY + 0.03), 0)
            crown.scale = SCNVector3(1, 0.8, 1)
            node.addChildNode(crown)
            let fold = SCNTorus(ringRadius: 0.148, pipeRadius: 0.022)
            fold.materials = [mat(color.darkened(0.12))]
            let fn = SCNNode(geometry: fold)
            fn.position = SCNVector3(0, Float(headY - 0.005), 0)
            fn.eulerAngles.x = .pi / 2
            node.addChildNode(fn)
        case "beret":
            let crown = SCNNode(geometry: SCNSphere(radius: 0.15))
            crown.geometry?.materials = [m]
            crown.position = SCNVector3(-0.03, Float(headY + 0.045), 0)
            crown.scale = SCNVector3(1.06, 0.5, 1.06)
            node.addChildNode(crown)
        case "bucket":
            let dome = SCNNode(geometry: SCNSphere(radius: 0.14))
            dome.geometry?.materials = [m]
            dome.position = SCNVector3(0, Float(headY + 0.04), 0)
            dome.scale = SCNVector3(1, 0.62, 1)
            node.addChildNode(dome)
            let brim = SCNNode(geometry: SCNCylinder(radius: 0.17, height: 0.012))
            brim.geometry?.materials = [m]
            brim.position = SCNVector3(0, Float(headY), 0)
            node.addChildNode(brim)

        case "sneakers", "leather", "boots":
            let isBoots = kind == "boots"
            for (_, x) in [("footL", CGFloat(-0.11)), ("footR", CGFloat(0.11))] {
                let shoe = SCNNode(geometry: SCNBox(width: 0.15, height: isBoots ? 0.16 : 0.09,
                                                    length: 0.25, chamferRadius: 0.035))
                shoe.geometry?.materials = [m]
                shoe.position = SCNVector3(Float(x), Float(isBoots ? 0.075 : 0.05), 0.05)
                node.addChildNode(shoe)
                if isBoots {
                    let cuff = SCNTube(innerRadius: 0.082, outerRadius: 0.096, height: 0.2)
                    cuff.materials = [md]
                    let cn = SCNNode(geometry: cuff)
                    cn.position = SCNVector3(Float(x), Float(0.24), 0.02)
                    node.addChildNode(cn)
                }
                let sole = SCNNode(geometry: SCNBox(width: 0.16, height: 0.02, length: 0.26, chamferRadius: 0.008))
                sole.geometry?.materials = [mat(UIColor(white: 0.92, alpha: 1))]
                sole.position = SCNVector3(Float(x), 0.01, 0.05)
                node.addChildNode(sole)
            }

        case "hairShort", "hairLong", "hairCurly", "hairPony":
            let cap = SCNNode(geometry: SCNSphere(radius: 0.162))
            cap.geometry?.materials = [m]
            cap.position = SCNVector3(0, Float(headY + 0.012), -0.006)
            cap.scale = SCNVector3(1.02, 0.95, 1.04)
            node.addChildNode(cap)
            if kind != "hairShort" {
                let back = SCNNode(geometry: SCNCapsule(capRadius: 0.075, height: kind == "hairLong" ? 0.5 : 0.24))
                back.geometry?.materials = [m]
                back.position = SCNVector3(0, Float(headY - (kind == "hairLong" ? 0.22 : 0.06)), -0.13)
                node.addChildNode(back)
            }
            if kind == "hairCurly" {
                for pt in [(-0.12, 0.05, 0.02), (0.12, 0.05, 0.02), (0.0, 0.1, -0.1), (-0.09, 0.08, -0.09), (0.09, 0.08, -0.09)] {
                    let curl = SCNNode(geometry: SCNSphere(radius: 0.055))
                    curl.geometry?.materials = [m]
                    curl.position = SCNVector3(Float(pt.0), Float(headY + pt.1), Float(pt.2))
                    node.addChildNode(curl)
                }
            }
            if kind == "hairPony" {
                let pony = SCNNode(geometry: SCNCapsule(capRadius: 0.04, height: 0.34))
                pony.geometry?.materials = [m]
                pony.position = SCNVector3(0, Float(headY - 0.14), -0.16)
                pony.eulerAngles.x = 0.25
                node.addChildNode(pony)
            }

        case "glasses":
            let frameM = mat(color, rough: 0.4, metal: 0.3)
            for x in [CGFloat(-0.06), CGFloat(0.06)] {
                let ring = SCNTorus(ringRadius: 0.035, pipeRadius: 0.006)
                ring.materials = [frameM]
                let rn = SCNNode(geometry: ring)
                rn.position = SCNVector3(Float(x), Float(headY + 0.005), 0.148)
                node.addChildNode(rn)
            }
            let bridge = SCNNode(geometry: SCNBox(width: 0.045, height: 0.008, length: 0.008, chamferRadius: 0.002))
            bridge.geometry?.materials = [frameM]
            bridge.position = SCNVector3(0, Float(headY + 0.01), 0.15)
            node.addChildNode(bridge)
        case "necklace":
            let ring = SCNTorus(ringRadius: 0.082, pipeRadius: 0.008)
            ring.materials = [mat(color, rough: 0.3, metal: 0.8)]
            let rn = SCNNode(geometry: ring)
            rn.position = SCNVector3(0, Float(legLen + 0.18 + 0.86), 0.03)
            rn.eulerAngles.x = 1.25
            node.addChildNode(rn)
        case "bag":
            let strap = SCNTorus(ringRadius: 0.2, pipeRadius: 0.009)
            strap.materials = [m]
            let sn = SCNNode(geometry: strap)
            sn.position = SCNVector3(0, Float(legLen + 0.18 + 0.62), 0)
            sn.eulerAngles = SCNVector3(1.35, 0, 0.35)
            node.addChildNode(sn)
            let bag = SCNNode(geometry: SCNBox(width: 0.14, height: 0.12, length: 0.05, chamferRadius: 0.02))
            bag.geometry?.materials = [m]
            bag.position = SCNVector3(-0.17, Float(legLen + 0.28), 0.06)
            node.addChildNode(bag)
        case "earring":
            for x in [CGFloat(-0.15), CGFloat(0.15)] {
                let gem = SCNNode(geometry: SCNSphere(radius: 0.016))
                gem.geometry?.materials = [mat(color, rough: 0.2, metal: 0.1)]
                gem.position = SCNVector3(Float(x), Float(headY - 0.02), 0.02)
                node.addChildNode(gem)
            }
        default:
            break
        }
        return node
    }

    static func colorFromHex(_ hex: String) -> (Double, Double, Double) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return (0.5, 0.5, 0.5) }
        return (Double((v >> 16) & 0xFF) / 255,
                Double((v >> 8) & 0xFF) / 255,
                Double(v & 0xFF) / 255)
    }

    private static func mat(_ color: UIColor, rough: CGFloat = 0.72, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }
}

extension UIColor {
    func darkened(_ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: max(0, b * (1 - amount)), alpha: a)
    }
}
