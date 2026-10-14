import SwiftUI
import RealityKit
import Combine

// MARK: - Doll Studio 3D 场景控制器
// 程序化 Q 版盲盒玩偶：真实 3D 几何（球体/胶囊/圆锥台组合），支持换装、调色、
// 轨道相机（360° 旋转 + 缩放）、快照导出、远程 USDZ 模型加载。

final class DollSceneController: NSObject, ObservableObject {
    let arView: ARView
    private let stage = AnchorEntity(world: .zero)
    private let cameraAnchor = AnchorEntity(world: .zero)
    private var dollRoot: Entity?
    private var armPivots: [Entity] = []
    private var slotAnchors: [String: Entity] = [:]
    private var remoteCancels: [String: AnyCancellable] = [:]
    private var appliedKey: String = ""
    /// 远程模型的基础地址（服务端根 URL），由视图注入
    var baseURL: String = ""

    // 相机轨道参数
    private var azimuth: Float = 0.30
    private var elevation: Float = 0.12
    private var radius: Float = 2.7
    private let target = SIMD3<Float>(0, 0.72, 0)
    private let defaultAzimuth: Float = 0.30
    private let defaultElevation: Float = 0.12
    private let defaultRadius: Float = 2.7

    override init() {
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        super.init()
        setup()
    }

    private func setup() {
        arView.environment.background = .color(UIColor(white: 0.965, alpha: 1))

        // 灯光：主光 + 辅光 + 轮廓光（Q 版塑料质感）
        let key = DirectionalLight()
        key.light.intensity = 2800
        key.orientation = simd_quatf(angle: -.pi / 3.2, axis: SIMD3<Float>(1, 0, 0))
        let keyAnchor = AnchorEntity(world: .zero)
        keyAnchor.addChild(key)
        keyAnchor.orientation = simd_quatf(angle: 0.7, axis: SIMD3<Float>(0, 1, 0))
        arView.scene.addAnchor(keyAnchor)

        let fill = DirectionalLight()
        fill.light.intensity = 1200
        fill.orientation = simd_quatf(angle: .pi / 2.6, axis: SIMD3<Float>(1, 0, 0))
        let fillAnchor = AnchorEntity(world: .zero)
        fillAnchor.addChild(fill)
        fillAnchor.orientation = simd_quatf(angle: -.pi * 0.62, axis: SIMD3<Float>(0, 1, 0))
        arView.scene.addAnchor(fillAnchor)

        // 相机
        cameraAnchor.addChild(PerspectiveCamera())
        arView.scene.addAnchor(cameraAnchor)
        updateCamera()

        // 展台
        arView.scene.addAnchor(stage)

        // 手势：单指旋转 / 双指缩放 / 双击复位
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        arView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        arView.addGestureRecognizer(pinch)
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        arView.addGestureRecognizer(dbl)
    }

    // MARK: 相机

    private func updateCamera() {
        let pos = target + SIMD3<Float>(
            radius * cos(elevation) * sin(azimuth),
            radius * sin(elevation),
            radius * cos(elevation) * cos(azimuth))
        cameraAnchor.look(at: target, from: pos, relativeTo: nil)
    }

    func resetView() {
        azimuth = defaultAzimuth
        elevation = defaultElevation
        radius = defaultRadius
        updateCamera()
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: arView)
        azimuth -= Float(t.x) * 0.012
        elevation = min(max(elevation + Float(t.y) * 0.008, -0.42), 1.15)
        g.setTranslation(.zero, in: arView)
        updateCamera()
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        radius = min(max(radius / Float(g.scale), 1.7), 5.5)
        g.scale = 1
        updateCamera()
    }

    @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        resetView()
    }

    // MARK: 换装应用（整体重建，几何量小、瞬时完成）

    func apply(state: DollOutfitState, lookup: [String: DollItem]) {
        let key = state.json + "|" + String(lookup.count)
        guard key != appliedKey else { return }
        appliedKey = key

        for c in remoteCancels.values { c.cancel() }
        remoteCancels.removeAll()
        dollRoot?.removeFromParent()
        armPivots.removeAll()
        slotAnchors.removeAll()

        let root = Entity()
        root.name = "doll"
        stage.addChild(root)
        dollRoot = root

        buildBody(into: root, state: state)

        for slot in ["hair", "top", "bottom", "scarf", "hat", "shoes", "accessory"] {
            let a = Entity()
            a.name = "slot-" + slot
            root.addChild(a)
            slotAnchors[slot] = a
        }

        let p = P.of(state.gender)
        for (cat, sel) in state.items {
            guard let anchor = slotAnchors[cat] else { continue }
            let item = lookup["\(cat)|\(sel.style)"]
            buildGarment(cat: cat, style: sel.style, hex: sel.color, p: p, anchor: anchor, arms: armPivots)
            if let urlStr = item?.modelUrl, !urlStr.isEmpty {
                loadRemoteModel(urlStr: urlStr, key: cat,
                                scale: Float(item?.modelScale ?? 1),
                                offsetY: Float(item?.modelOffsetY ?? 0),
                                into: anchor)
            }
        }
    }

    // MARK: 玩偶身材参数（男性 / 女性 / 中性 Q 版）

    struct P {
        var headR: Float
        var headY: Float
        var shoulderX: Float
        var torsoR: Float
        var hipWide: Float
        var legR: Float
        var armR: Float

        static func of(_ gender: String) -> P {
            switch gender {
            case "male":
                return P(headR: 0.30, headY: 1.14, shoulderX: 0.205, torsoR: 0.155, hipWide: 0.95, legR: 0.077, armR: 0.052)
            case "female":
                return P(headR: 0.30, headY: 1.14, shoulderX: 0.168, torsoR: 0.142, hipWide: 1.14, legR: 0.068, armR: 0.046)
            default:
                return P(headR: 0.30, headY: 1.14, shoulderX: 0.185, torsoR: 0.148, hipWide: 1.0, legR: 0.072, armR: 0.049)
            }
        }
    }

    // MARK: 几何 / 材质工具

    /// 程序化胶囊网格（iOS 26 SDK 移除了 MeshResource.generateCapsule，用 MeshDescriptor 自建，
    /// 外形与原生成器一致：中间圆柱段 + 上下半球端盖，总高 = height + 2*radius）
    private func capsuleMesh(height: Float, radius: Float, segments: Int = 24) -> MeshResource {
        let halfH = height / 2
        let rings = 10
        // 轮廓：顶极点 → 顶半球 → 圆柱 → 底半球 → 底极点（y, 半径）
        var profile: [(y: Float, r: Float)] = []
        for i in 0...rings {
            let a = Float(i) / Float(rings) * Float.pi / 2
            profile.append((cos(a) * radius + halfH, sin(a) * radius))
        }
        for i in 1...rings {
            let a = Float.pi / 2 + Float(i) / Float(rings) * Float.pi / 2
            profile.append((cos(a) * radius - halfH, sin(a) * radius))
        }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let n = profile.count
        for p in profile {
            for j in 0..<segments {
                let a = Float(j) / Float(segments) * 2 * Float.pi
                let x = cos(a) * p.r, z = sin(a) * p.r
                positions.append(SIMD3<Float>(x, p.y, z))
                // 法线：端部按球心，中段按径向
                if p.y > halfH {
                    normals.append(SIMD3<Float>(x, p.y - halfH, z))
                } else if p.y < -halfH {
                    normals.append(SIMD3<Float>(x, p.y + halfH, z))
                } else {
                    normals.append(SIMD3<Float>(x, 0, z))
                }
            }
        }
        for i in 0..<(n - 1) {
            for j in 0..<segments {
                let j2 = (j + 1) % segments
                let a0 = UInt32(i * segments + j)
                let a1 = UInt32(i * segments + j2)
                let b0 = UInt32((i + 1) * segments + j)
                let b1 = UInt32((i + 1) * segments + j2)
                indices += [a0, b0, b1, a0, b1, a1]
            }
        }
        var desc = MeshDescriptor(name: "capsule")
        desc.positions = MeshBuffers.Positions(positions)
        desc.normals = MeshBuffers.Normals(normals)
        desc.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [desc])) ?? MeshResource.generateSphere(radius: max(radius, 0.001))
    }

    /// 旋转体网格（profile: 从底到顶的 (y, r) 轮廓；iOS 26 SDK 移除了 generateCone，用于锥台/锥体）
    private func latheMesh(profile: [(y: Float, r: Float)], segments: Int = 24, capTop: Bool = false, capBottom: Bool = false) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let n = profile.count
        for p in profile {
            for j in 0..<segments {
                let a = Float(j) / Float(segments) * 2 * Float.pi
                positions.append(SIMD3<Float>(cos(a) * p.r, p.y, sin(a) * p.r))
            }
        }
        // 侧面法线：轮廓切向 (dr, dy) → 外法线 (dy, -dr)
        for i in 0..<n {
            let y0 = profile[max(i - 1, 0)].y, y1 = profile[min(i + 1, n - 1)].y
            let r0 = profile[max(i - 1, 0)].r, r1 = profile[min(i + 1, n - 1)].r
            let dy = y1 - y0, dr = r1 - r0
            let len = sqrt(dy * dy + dr * dr)
            let nr: Float = len > 0.0001 ? dy / len : 1
            let ny: Float = len > 0.0001 ? -dr / len : 0
            for j in 0..<segments {
                let a = Float(j) / Float(segments) * 2 * Float.pi
                normals.append(SIMD3<Float>(cos(a) * nr, ny, sin(a) * nr))
            }
        }
        for i in 0..<(n - 1) {
            for j in 0..<segments {
                let j2 = (j + 1) % segments
                let a0 = UInt32(i * segments + j)
                let a1 = UInt32(i * segments + j2)
                let b0 = UInt32((i + 1) * segments + j)
                let b1 = UInt32((i + 1) * segments + j2)
                indices += [a0, b0, b1, a0, b1, a1]
            }
        }
        if capBottom, let base = profile.first, base.r > 0.001 {
            let ci = UInt32(positions.count)
            positions.append(SIMD3<Float>(0, base.y, 0))
            normals.append(SIMD3<Float>(0, -1, 0))
            for j in 0..<segments {
                let a = Float(j) / Float(segments) * 2 * Float.pi
                positions.append(SIMD3<Float>(cos(a) * base.r, base.y, sin(a) * base.r))
                normals.append(SIMD3<Float>(0, -1, 0))
            }
            for j in 0..<segments {
                let j2 = (j + 1) % segments
                indices += [ci, UInt32(ci + 1 + j2), UInt32(ci + 1 + j)]
            }
        }
        if capTop, let top = profile.last, top.r > 0.001 {
            let ci = UInt32(positions.count)
            positions.append(SIMD3<Float>(0, top.y, 0))
            normals.append(SIMD3<Float>(0, 1, 0))
            for j in 0..<segments {
                let a = Float(j) / Float(segments) * 2 * Float.pi
                positions.append(SIMD3<Float>(cos(a) * top.r, top.y, sin(a) * top.r))
                normals.append(SIMD3<Float>(0, 1, 0))
            }
            for j in 0..<segments {
                let j2 = (j + 1) % segments
                indices += [ci, UInt32(ci + 1 + j), UInt32(ci + 1 + j2)]
            }
        }
        var desc = MeshDescriptor(name: "lathe")
        desc.positions = MeshBuffers.Positions(positions)
        desc.normals = MeshBuffers.Normals(normals)
        desc.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [desc])) ?? MeshResource.generateSphere(radius: 0.1)
    }

    private func material(_ hex: String, rough: Float = 0.62, metal: Float = 0.0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: DollColor.ui(hex))
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        return m
    }

    private func mesh(_ m: MeshResource, _ mat: PhysicallyBasedMaterial, _ pos: SIMD3<Float>,
                      scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1), quat: simd_quatf? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: m, materials: [mat])
        e.position = pos
        e.scale = scale
        if let quat { e.orientation = quat }
        return e
    }

    private func rotZ(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: SIMD3<Float>(0, 0, 1)) }
    private func rotX(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: SIMD3<Float>(1, 0, 0)) }

    // MARK: 身体（头/脸/躯干/四肢 + 展台）

    private func buildBody(into root: Entity, state: DollOutfitState) {
        let p = P.of(state.gender)
        let skin = material(state.skin, rough: 0.55)

        // 展台圆盘
        root.addChild(mesh(.generateSphere(radius: 0.62),
                           material("#E9E9EF", rough: 0.9), SIMD3<Float>(0, 0.015, 0), scale: SIMD3<Float>(1, 0.048, 1)))

        // 腿 + 脚掌（皮肤）
        for sx in [Float(-1), 1] {
            let pivot = Entity()
            pivot.position = SIMD3<Float>(sx * 0.082, 0.50, 0)
            root.addChild(pivot)
            pivot.addChild(mesh(capsuleMesh(height: 0.36, radius: p.legR), skin, SIMD3<Float>(0, -0.21, 0)))
            pivot.addChild(mesh(.generateBox(size: SIMD3<Float>(0.13, 0.06, 0.22), cornerRadius: 0.028),
                                material(state.skin, rough: 0.6), SIMD3<Float>(0, -0.452, 0.045)))
        }

        // 髋 + 躯干
        root.addChild(mesh(.generateSphere(radius: p.torsoR + 0.02), skin,
                           SIMD3<Float>(0, 0.50, 0), scale: SIMD3<Float>(p.hipWide, 0.78, 0.9)))
        root.addChild(mesh(capsuleMesh(height: 0.26, radius: p.torsoR), skin,
                           SIMD3<Float>(0, 0.665, 0), scale: SIMD3<Float>(1.06, 1.0, 0.88)))

        // 肩 + 手臂（枢轴供衣袖挂载）
        for sx in [Float(-1), 1] {
            root.addChild(mesh(.generateSphere(radius: 0.058), skin, SIMD3<Float>(sx * p.shoulderX, 0.80, 0)))
            let pivot = Entity()
            pivot.position = SIMD3<Float>(sx * p.shoulderX, 0.795, 0)
            pivot.orientation = rotZ(sx * 0.10)
            root.addChild(pivot)
            pivot.addChild(mesh(capsuleMesh(height: 0.26, radius: p.armR), skin, SIMD3<Float>(0, -0.155, 0)))
            pivot.addChild(mesh(.generateSphere(radius: p.armR + 0.009), skin, SIMD3<Float>(0, -0.325, 0)))
            armPivots.append(pivot)
        }

        // 颈 + 头
        root.addChild(mesh(.generateSphere(radius: 0.078), skin, SIMD3<Float>(0, 0.855, 0), scale: SIMD3<Float>(1, 0.72, 1)))
        root.addChild(mesh(.generateSphere(radius: p.headR), skin,
                           SIMD3<Float>(0, 1.14, 0), scale: SIMD3<Float>(0.96, 1.02, 0.96)))

        // 脸：眼睛 + 高光 + 腮红 + 嘴 + 耳朵
        let eyeMat = material("#2C2C2E", rough: 0.22)
        for sx in [Float(-1), 1] {
            root.addChild(mesh(.generateSphere(radius: 0.045), eyeMat,
                               SIMD3<Float>(sx * 0.105, 1.175, 0.268), scale: SIMD3<Float>(1, 1.15, 0.42)))
            root.addChild(mesh(.generateSphere(radius: 0.013), material("#FFFFFF", rough: 0.1),
                               SIMD3<Float>(sx * 0.082, 1.198, 0.289)))
            root.addChild(mesh(.generateSphere(radius: 0.05), material("#FFB3B3", rough: 0.85),
                               SIMD3<Float>(sx * 0.175, 1.098, 0.225), scale: SIMD3<Float>(1, 0.6, 0.35)))
            root.addChild(mesh(.generateSphere(radius: 0.06), skin,
                               SIMD3<Float>(sx * 0.285, 1.128, 0.0), scale: SIMD3<Float>(0.5, 0.78, 0.55)))
        }
        root.addChild(mesh(.generateSphere(radius: 0.028), material("#B06A5E", rough: 0.6),
                           SIMD3<Float>(0, 1.048, 0.268), scale: SIMD3<Float>(1.2, 0.62, 0.4)))
    }

    // MARK: 服装构建（程序化 3D 款式，全部真实几何网格）

    private func buildGarment(cat: String, style: String, hex: String, p: P, anchor: Entity, arms: [Entity]) {
        switch cat {
        case "hair": buildHair(style, hex: hex, p: p, into: anchor)
        case "top": buildTop(style, hex: hex, p: p, into: anchor, arms: arms)
        case "bottom": buildBottom(style, hex: hex, p: p, into: anchor)
        case "scarf": buildScarf(style, hex: hex, into: anchor)
        case "hat": buildHat(style, hex: hex, into: anchor)
        case "shoes": buildShoes(style, hex: hex, into: anchor)
        case "accessory": buildAccessory(style, hex: hex, into: anchor)
        default: break
        }
    }

    /// 头发基础壳（头顶半球 + 刘海）
    private func hairCap(_ m: PhysicallyBasedMaterial, into e: Entity, puffy: Float = 0.318) {
        e.addChild(mesh(.generateSphere(radius: puffy), m,
                        SIMD3<Float>(0, 1.168, -0.02), scale: SIMD3<Float>(1.0, 0.92, 1.02)))
        e.addChild(mesh(.generateSphere(radius: 0.235), m,
                        SIMD3<Float>(0, 1.292, 0.112), scale: SIMD3<Float>(1.12, 0.5, 0.82)))
    }

    private func buildHair(_ style: String, hex: String, p: P, into e: Entity) {
        let m = material(hex, rough: 0.72)
        switch style {
        case "bob":
            hairCap(m, into: e)
            for sx in [Float(-1), 1] {
                e.addChild(mesh(capsuleMesh(height: 0.14, radius: 0.085), m,
                                SIMD3<Float>(sx * 0.255, 1.06, 0.02), scale: SIMD3<Float>(0.9, 1, 0.8)))
            }
            e.addChild(mesh(capsuleMesh(height: 0.10, radius: 0.16), m,
                            SIMD3<Float>(0, 1.02, -0.15), scale: SIMD3<Float>(1.25, 1, 0.55)))
        case "long":
            hairCap(m, into: e)
            e.addChild(mesh(capsuleMesh(height: 0.34, radius: 0.15), m,
                            SIMD3<Float>(0, 0.86, -0.165), scale: SIMD3<Float>(1.28, 1, 0.5)))
            for sx in [Float(-1), 1] {
                e.addChild(mesh(capsuleMesh(height: 0.20, radius: 0.06), m,
                                SIMD3<Float>(sx * 0.25, 0.94, 0.0), scale: SIMD3<Float>(0.9, 1, 0.8)))
            }
        case "twintails":
            hairCap(m, into: e)
            for sx in [Float(-1), 1] {
                let tail = Entity()
                tail.position = SIMD3<Float>(sx * 0.30, 1.24, -0.04)
                tail.orientation = rotZ(sx * 0.26)
                e.addChild(tail)
                tail.addChild(mesh(capsuleMesh(height: 0.24, radius: 0.062), m, SIMD3<Float>(0, -0.17, 0)))
                tail.addChild(mesh(.generateSphere(radius: 0.05), material("#FFFFFF", rough: 0.7), SIMD3<Float>(0, -0.015, 0)))
            }
        case "bun":
            hairCap(m, into: e)
            e.addChild(mesh(.generateSphere(radius: 0.115), m, SIMD3<Float>(0, 1.445, -0.05)))
            e.addChild(mesh(.generateSphere(radius: 0.10), material("#FFFFFF", rough: 0.7),
                            SIMD3<Float>(0, 1.365, -0.035), scale: SIMD3<Float>(1, 0.35, 1)))
        case "spiky":
            hairCap(m, into: e, puffy: 0.312)
            for i in 0..<5 {
                let a = Float(i) / 5.0 * 2.0 * Float.pi
                let dir = SIMD3<Float>(cos(a), 0, sin(a))
                let axis = SIMD3<Float>(-sin(a), 0, cos(a))
                e.addChild(mesh(latheMesh(profile: [(y: -0.085, r: 0.055), (y: 0.085, r: 0.004)]), m,
                                SIMD3<Float>(dir.x * 0.13, 1.40, dir.z * 0.13 - 0.02),
                                quat: simd_quatf(angle: 0.38, axis: axis)))
            }
        default: // short 短发
            hairCap(m, into: e)
        }
    }

    private func buildTop(_ style: String, hex: String, p: P, into e: Entity, arms: [Entity]) {
        let m = material(hex, rough: 0.7)
        switch style {
        case "hoodie":
            e.addChild(mesh(capsuleMesh(height: 0.28, radius: p.torsoR + 0.028), m,
                            SIMD3<Float>(0, 0.665, 0), scale: SIMD3<Float>(1.1, 1.0, 0.92)))
            for pivot in arms {
                pivot.addChild(mesh(capsuleMesh(height: 0.22, radius: p.armR + 0.017), m, SIMD3<Float>(0, -0.17, 0)))
            }
            e.addChild(mesh(.generateSphere(radius: 0.16), m, SIMD3<Float>(0, 0.875, -0.105),
                            scale: SIMD3<Float>(1.15, 0.72, 0.85)))
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.17, 0.10, 0.05), cornerRadius: 0.025), m,
                            SIMD3<Float>(0, 0.565, 0.152)))
        case "shirt":
            e.addChild(mesh(capsuleMesh(height: 0.27, radius: p.torsoR + 0.013), m,
                            SIMD3<Float>(0, 0.665, 0), scale: SIMD3<Float>(1.08, 1.0, 0.9)))
            for pivot in arms {
                pivot.addChild(mesh(capsuleMesh(height: 0.22, radius: p.armR + 0.015), m, SIMD3<Float>(0, -0.17, 0)))
            }
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.07, 0.05, 0.02), cornerRadius: 0.008), m,
                                SIMD3<Float>(sx * 0.045, 0.818, 0.138), quat: rotZ(sx * 0.5)))
            }
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.022, 0.22, 0.014), cornerRadius: 0.006),
                            material("#FFFFFF", rough: 0.5), SIMD3<Float>(0, 0.70, 0.148)))
        case "vest":
            e.addChild(mesh(capsuleMesh(height: 0.27, radius: p.torsoR + 0.018), m,
                            SIMD3<Float>(0, 0.665, 0), scale: SIMD3<Float>(1.06, 1.0, 0.88)))
            e.addChild(mesh(.generateSphere(radius: 0.10), m, SIMD3<Float>(0, 0.825, 0), scale: SIMD3<Float>(1, 0.5, 1)))
        case "sweater":
            e.addChild(mesh(capsuleMesh(height: 0.27, radius: p.torsoR + 0.02), m,
                            SIMD3<Float>(0, 0.66, 0), scale: SIMD3<Float>(1.08, 1.0, 0.9)))
            for pivot in arms {
                pivot.addChild(mesh(capsuleMesh(height: 0.22, radius: p.armR + 0.016), m, SIMD3<Float>(0, -0.17, 0)))
            }
            e.addChild(mesh(.generateSphere(radius: 0.095), m, SIMD3<Float>(0, 0.848, 0), scale: SIMD3<Float>(1, 0.74, 1)))
            e.addChild(mesh(.generateSphere(radius: p.torsoR + 0.032), m,
                            SIMD3<Float>(0, 0.545, 0), scale: SIMD3<Float>(1.05, 0.42, 0.9)))
        case "jacket":
            e.addChild(mesh(capsuleMesh(height: 0.28, radius: p.torsoR + 0.022), m,
                            SIMD3<Float>(0, 0.66, 0), scale: SIMD3<Float>(1.1, 1.0, 0.92)))
            for pivot in arms {
                pivot.addChild(mesh(capsuleMesh(height: 0.22, radius: p.armR + 0.016), m, SIMD3<Float>(0, -0.17, 0)))
            }
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.075, 0.045, 0.02), cornerRadius: 0.008), m,
                                SIMD3<Float>(sx * 0.05, 0.822, 0.14), quat: rotZ(sx * 0.55)))
            }
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.024, 0.24, 0.014), cornerRadius: 0.006),
                            material("#C9CDD4", rough: 0.4), SIMD3<Float>(0, 0.685, 0.152)))
        default: // tee 经典T恤
            e.addChild(mesh(capsuleMesh(height: 0.26, radius: p.torsoR + 0.014), m,
                            SIMD3<Float>(0, 0.665, 0), scale: SIMD3<Float>(1.08, 1.0, 0.9)))
            for pivot in arms {
                pivot.addChild(mesh(capsuleMesh(height: 0.12, radius: p.armR + 0.013), m, SIMD3<Float>(0, -0.105, 0)))
            }
        }
    }

    private func buildBottom(_ style: String, hex: String, p: P, into e: Entity) {
        let m = material(hex, rough: 0.7)
        switch style {
        case "pants":
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.30, 0.16, 0.21), cornerRadius: 0.06), m,
                            SIMD3<Float>(0, 0.50, 0), scale: SIMD3<Float>(p.hipWide, 1, 1)))
            for sx in [Float(-1), 1] {
                e.addChild(mesh(capsuleMesh(height: 0.22, radius: p.legR + 0.014), m, SIMD3<Float>(sx * 0.082, 0.31, 0)))
            }
        case "skirt":
            e.addChild(mesh(latheMesh(profile: [(y: -0.15, r: 0.235), (y: 0.155, r: 0.02)], capBottom: true), m,
                            SIMD3<Float>(0, 0.40, 0), scale: SIMD3<Float>(1.05, 1, 0.85)))
            e.addChild(mesh(.generateSphere(radius: p.torsoR), m,
                            SIMD3<Float>(0, 0.545, 0), scale: SIMD3<Float>(1.04, 0.42, 0.9)))
        case "wide_leg":
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.30, 0.16, 0.21), cornerRadius: 0.06), m,
                            SIMD3<Float>(0, 0.50, 0), scale: SIMD3<Float>(p.hipWide, 1, 1)))
            for sx in [Float(-1), 1] {
                e.addChild(mesh(capsuleMesh(height: 0.20, radius: p.legR + 0.042), m, SIMD3<Float>(sx * 0.082, 0.31, 0)))
            }
        default: // shorts 短裤
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.30, 0.14, 0.21), cornerRadius: 0.055), m,
                            SIMD3<Float>(0, 0.495, 0), scale: SIMD3<Float>(p.hipWide, 1, 1)))
            for sx in [Float(-1), 1] {
                e.addChild(mesh(capsuleMesh(height: 0.05, radius: p.legR + 0.012), m, SIMD3<Float>(sx * 0.082, 0.42, 0)))
            }
        }
    }

    private func buildScarf(_ style: String, hex: String, into e: Entity) {
        let m = material(hex, rough: 0.78)
        switch style {
        case "bandana":
            e.addChild(mesh(latheMesh(profile: [(y: 0.085, r: 0.15), (y: -0.085, r: 0.004)]), m,
                            SIMD3<Float>(0, 0.775, 0.148), scale: SIMD3<Float>(1.15, 1, 0.55)))
            e.addChild(mesh(.generateSphere(radius: 0.045), m, SIMD3<Float>(0, 0.862, 0.135)))
        default: // scarf 经典围巾
            e.addChild(mesh(.generateSphere(radius: 0.135), m, SIMD3<Float>(0, 0.855, 0), scale: SIMD3<Float>(1, 0.74, 1)))
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.09, 0.24, 0.04), cornerRadius: 0.02), m,
                            SIMD3<Float>(0.055, 0.72, 0.14), quat: rotZ(0.12)))
        }
    }

    private func buildHat(_ style: String, hex: String, into e: Entity) {
        let m = material(hex, rough: 0.72)
        switch style {
        case "cap":
            e.addChild(mesh(.generateSphere(radius: 0.31), m, SIMD3<Float>(0, 1.17, -0.015), scale: SIMD3<Float>(1.0, 0.62, 1.0)))
            e.addChild(mesh(.generateSphere(radius: 0.20), m,
                            SIMD3<Float>(0, 1.222, 0.24), scale: SIMD3<Float>(1.2, 0.12, 0.8)))
            e.addChild(mesh(.generateSphere(radius: 0.045), m, SIMD3<Float>(0, 1.352, -0.01)))
        case "bucket":
            e.addChild(mesh(.generateSphere(radius: 0.29), m, SIMD3<Float>(0, 1.265, 0), scale: SIMD3<Float>(1, 0.52, 1)))
            e.addChild(mesh(.generateSphere(radius: 0.33), m, SIMD3<Float>(0, 1.19, 0), scale: SIMD3<Float>(1, 0.075, 1)))
        case "beret":
            e.addChild(mesh(.generateSphere(radius: 0.29), m, SIMD3<Float>(0, 1.305, -0.02),
                            scale: SIMD3<Float>(1.15, 0.5, 1.08), quat: rotZ(0.10)))
            e.addChild(mesh(.generateSphere(radius: 0.045), m, SIMD3<Float>(0, 1.415, -0.02)))
        default: // beanie 毛线帽
            e.addChild(mesh(.generateSphere(radius: 0.315), m, SIMD3<Float>(0, 1.20, -0.01), scale: SIMD3<Float>(1.0, 0.75, 1.0)))
            e.addChild(mesh(.generateSphere(radius: 0.318), m, SIMD3<Float>(0, 1.21, 0), scale: SIMD3<Float>(1, 0.28, 1)))
            e.addChild(mesh(.generateSphere(radius: 0.07), material("#FFFFFF", rough: 0.9), SIMD3<Float>(0, 1.475, 0)))
        }
    }

    private func buildShoes(_ style: String, hex: String, into e: Entity) {
        let m = material(hex, rough: 0.6)
        switch style {
        case "boots":
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.15, 0.20, 0.23), cornerRadius: 0.035), m,
                                SIMD3<Float>(sx * 0.082, 0.135, 0.04)))
                e.addChild(mesh(capsuleMesh(height: 0.05, radius: 0.088), m, SIMD3<Float>(sx * 0.082, 0.28, 0)))
            }
        case "loafers":
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.14, 0.10, 0.23), cornerRadius: 0.045), m,
                                SIMD3<Float>(sx * 0.082, 0.075, 0.045)))
            }
        case "sandals":
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.14, 0.035, 0.23), cornerRadius: 0.015), m,
                                SIMD3<Float>(sx * 0.082, 0.05, 0.045)))
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.13, 0.02, 0.05), cornerRadius: 0.008), m,
                                SIMD3<Float>(sx * 0.082, 0.085, 0.09)))
            }
        default: // sneakers 小白鞋
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.15, 0.11, 0.24), cornerRadius: 0.04), m,
                                SIMD3<Float>(sx * 0.082, 0.095, 0.05)))
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.155, 0.035, 0.245), cornerRadius: 0.015),
                                material("#F5F5F0", rough: 0.8), SIMD3<Float>(sx * 0.082, 0.028, 0.05)))
            }
        }
    }

    private func buildAccessory(_ style: String, hex: String, into e: Entity) {
        switch style {
        case "glasses":
            let dark = material("#2C2C2E", rough: 0.25)
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateSphere(radius: 0.062), dark,
                                SIMD3<Float>(sx * 0.105, 1.175, 0.292), scale: SIMD3<Float>(1, 1, 0.12)))
            }
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.09, 0.014, 0.014), cornerRadius: 0.006), dark,
                            SIMD3<Float>(0, 1.185, 0.292)))
        case "necklace":
            let gold = material(hex, rough: 0.25, metal: 0.85)
            e.addChild(mesh(.generateSphere(radius: 0.042), gold, SIMD3<Float>(0, 0.735, 0.15)))
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.16, 0.012, 0.012), cornerRadius: 0.005), gold,
                                SIMD3<Float>(sx * 0.078, 0.778, 0.128), quat: rotZ(sx * 0.5)))
            }
        case "backpack":
            let m = material(hex, rough: 0.7)
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.26, 0.32, 0.14), cornerRadius: 0.05), m,
                            SIMD3<Float>(0, 0.64, -0.20)))
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.035, 0.22, 0.02), cornerRadius: 0.01), m,
                                SIMD3<Float>(sx * 0.105, 0.80, -0.148)))
            }
        case "earrings":
            let gold = material(hex, rough: 0.3, metal: 0.7)
            for sx in [Float(-1), 1] {
                e.addChild(mesh(.generateSphere(radius: 0.03), gold, SIMD3<Float>(sx * 0.29, 1.095, 0.012)))
            }
        case "flower":
            let m = material(hex, rough: 0.75)
            let center = SIMD3<Float>(0.205, 1.385, 0.115)
            for i in 0..<3 {
                let a = Float(i) / 3.0 * 2.0 * Float.pi
                e.addChild(mesh(.generateSphere(radius: 0.042), m,
                                center + SIMD3<Float>(cos(a) * 0.04, sin(a) * 0.04, 0)))
            }
            e.addChild(mesh(.generateSphere(radius: 0.028), material("#FFD34D", rough: 0.7), center))
        default: // watch 运动手表
            let m = material(hex, rough: 0.4)
            e.addChild(mesh(.generateSphere(radius: 0.05), m,
                            SIMD3<Float>(-0.205, 0.47, 0.005), scale: SIMD3<Float>(0.4, 1, 1)))
            e.addChild(mesh(.generateBox(size: SIMD3<Float>(0.015, 0.09, 0.06), cornerRadius: 0.005), m,
                            SIMD3<Float>(-0.205, 0.47, 0.0)))
        }
    }

    // MARK: 远程 USDZ 模型（管理台上传的自定义模型；加载失败静默保留程序化几何）

    private func loadRemoteModel(urlStr: String, key: String, scale: Float, offsetY: Float, into anchor: Entity) {
        let full: URL?
        if urlStr.hasPrefix("http://") || urlStr.hasPrefix("https://") {
            full = URL(string: urlStr)
        } else if !baseURL.isEmpty {
            full = URL(string: baseURL + urlStr)
        } else {
            full = nil
        }
        guard let url = full else { return }
        remoteCancels[key]?.cancel()
        remoteCancels[key] = Entity.loadAsync(contentsOf: url).sink(
            receiveCompletion: { _ in },
            receiveValue: { entity in
                DispatchQueue.main.async {
                    entity.scale = SIMD3<Float>(repeating: max(scale, 0.01))
                    entity.position.y += offsetY
                    anchor.addChild(entity)
                }
            })
    }

    // MARK: 快照导出（导出图片 / 分享）

    func snapshot(_ completion: @escaping (UIImage?) -> Void) {
        arView.snapshot(saveToHDR: false) { image in
            DispatchQueue.main.async { completion(image) }
        }
    }
}

// MARK: - SwiftUI 包装（ARView 非AR模式：无需相机权限）

struct DollSceneView: UIViewRepresentable {
    @ObservedObject var controller: DollSceneController

    func makeUIView(context: Context) -> ARView { controller.arView }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
