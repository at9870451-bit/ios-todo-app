// DollStudio3D — OutfitStore：全局状态中枢（穿搭/撤销重做/收藏/作品/目录/持久化）
import SwiftUI
import Combine

@MainActor
final class OutfitStore: ObservableObject {
    // MARK: - 目录
    @Published var catalog: [ClothItem] = BuiltInCatalog.clothes
    @Published var categories: [ClothCategory] = ClothCategory.builtIn
    @Published var remoteCatalogLoaded = false
    @Published var loadError: String?

    // MARK: - 玩偶当前状态
    @Published var gender: DollGender = .female {
        didSet { persistCurrent() }
    }
    @Published var skin: String = "#F3C6A5" { didSet { persistCurrent() } }
    @Published var heightScale: Double = 1.0 { didSet { persistCurrent() } }
    @Published var dollName: String = "小雅" { didSet { persistCurrent() } }
    @Published var slots: [String: OutfitSlot] = [:] { didSet { persistCurrent() } }

    // MARK: - 收藏 / 最近使用 / 已解锁
    @Published var favorites: Set<String> = []
    @Published var recent: [String] = []
    @Published var owned: Set<String> = []          // 付费服装解锁（本地模拟，正式接服务端）

    // MARK: - 作品
    @Published var outfits: [Outfit] = []

    // MARK: - 撤销 / 重做
    private var undoStack: [[String: OutfitSlot]] = []
    private var redoStack: [[String: OutfitSlot]] = []
    @Published var canUndo = false
    @Published var canRedo = false

    // MARK: - 账户
    @Published var authToken: String?
    @Published var username: String = "游客"

    // MARK: - 持久化 key
    private let kCurrent = "doll.current.v1"
    private let kFavorites = "doll.favorites.v1"
    private let kRecent = "doll.recent.v1"
    private let kOwned = "doll.owned.v1"
    private let kOutfits = "doll.outfits.v1"
    private let kToken = "doll.token.v1"
    private let kUsername = "doll.username.v1"
    private let kAPIBase = "doll.apiBase.v1"

    var apiBase: String {
        get { UserDefaults.standard.string(forKey: kAPIBase) ?? "https://your-server.example.com" }
        set { UserDefaults.standard.set(newValue, forKey: kAPIBase) }
    }

    // MARK: - init

    init() {
        loadPersisted()
        applyDefaultOutfit(recordUndo: false)
    }

    func loadPersisted() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: kCurrent),
           let cur = try? JSONDecoder().decode(CurrentDoll.self, from: data) {
            gender = cur.gender; skin = cur.skin
            heightScale = cur.heightScale; dollName = cur.dollName
            slots = cur.slots
        }
        favorites = Set(d.stringArray(forKey: kFavorites) ?? [])
        recent = d.stringArray(forKey: kRecent) ?? []
        owned = Set(d.stringArray(forKey: kOwned) ?? [])
        if let data = d.data(forKey: kOutfits),
           let list = try? JSONDecoder().decode([Outfit].self, from: data) {
            outfits = list
        }
        authToken = d.string(forKey: kToken)
        username = d.string(forKey: kUsername) ?? "游客"
    }

    private struct CurrentDoll: Codable {
        var gender: DollGender
        var skin: String
        var heightScale: Double
        var dollName: String
        var slots: [String: OutfitSlot]
    }

    func persistCurrent() {
        let cur = CurrentDoll(gender: gender, skin: skin, heightScale: heightScale,
                              dollName: dollName, slots: slots)
        if let data = try? JSONEncoder().encode(cur) {
            UserDefaults.standard.set(data, forKey: kCurrent)
        }
    }

    // MARK: - 穿搭操作

    private func pushUndo() {
        undoStack.append(slots)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        syncUndoFlags()
    }

    private func syncUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(slots)
        slots = prev
        syncUndoFlags()
        AudioService.shared.play(.tap)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(slots)
        slots = next
        syncUndoFlags()
        AudioService.shared.play(.tap)
    }

    /// 穿上服装（互斥组检查 + 付费检查 + 最近使用）
    func select(_ item: ClothItem) {
        guard canWear(item) else { return }
        pushUndo()
        if let group = item.exclusiveGroup {
            // 同互斥组先移除
            for (cat, slot) in slots {
                if let cur = catalog.first(where: { $0.id == slot.clothId }),
                   cur.exclusiveGroup == group, cat != item.category {
                    slots.removeValue(forKey: cat)
                }
            }
        }
        slots[item.category] = OutfitSlot(clothId: item.id, color: item.color)
        recordRecent(item.id)
        AudioService.shared.play(.dress)
    }

    func canWear(_ item: ClothItem) -> Bool {
        item.isFree || owned.contains(item.id)
    }

    func setColor(_ hex: String, for category: String) {
        guard var slot = slots[category] else { return }
        pushUndo()
        slot.color = hex
        slots[category] = slot
    }

    func removeSlot(category: String) {
        guard slots[category] != nil else { return }
        pushUndo()
        slots.removeValue(forKey: category)
        AudioService.shared.play(.tap)
    }

    func resetOutfit() {
        pushUndo()
        applyDefaultOutfit(recordUndo: false)
        AudioService.shared.play(.tap)
    }

    func applyDefaultOutfit(recordUndo: Bool) {
        let defaults = ["top": "top_tee_white", "bottom": "bot_jeans_blue", "shoes": "shoe_sneakers_white"]
        var s: [String: OutfitSlot] = [:]
        for (cat, id) in defaults {
            if let item = catalog.first(where: { $0.id == id }) {
                s[cat] = OutfitSlot(clothId: item.id, color: item.color)
            }
        }
        slots = s
    }

    func applySlotsDirect(_ newSlots: [String: OutfitSlot]) {
        pushUndo()
        slots = newSlots
    }

    // MARK: - 收藏 / 最近

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: kFavorites)
    }

    private func recordRecent(_ id: String) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if recent.count > 20 { recent.removeLast() }
        UserDefaults.standard.set(recent, forKey: kRecent)
    }

    // MARK: - 解锁（本地模拟；正式版走服务端订单）

    func purchase(_ item: ClothItem) {
        owned.insert(item.id)
        UserDefaults.standard.set(Array(owned), forKey: kOwned)
        AudioService.shared.play(.success)
    }

    // MARK: - 作品

    func saveOutfit(named name: String) -> Outfit {
        let o = Outfit(name: name.isEmpty ? dollName + " 的穿搭" : name,
                       gender: gender, dollId: currentDollId, skin: skin, slots: slots)
        outfits.insert(o, at: 0)
        if outfits.count > 100 { outfits.removeLast() }
        if let data = try? JSONEncoder().encode(outfits) {
            UserDefaults.standard.set(data, forKey: kOutfits)
        }
        AudioService.shared.play(.success)
        return o
    }

    func loadOutfit(_ o: Outfit) {
        gender = o.gender
        skin = o.skin
        slots = o.slots
        persistCurrent()
    }

    func deleteOutfit(_ o: Outfit) {
        outfits.removeAll { $0.id == o.id }
        if let data = try? JSONEncoder().encode(outfits) {
            UserDefaults.standard.set(data, forKey: kOutfits)
        }
    }

    func duplicateOutfit(_ o: Outfit) {
        var copy = o
        copy.id = UUID().uuidString
        copy.name = o.name + " 副本"
        copy.createdAt = Date()
        outfits.insert(copy, at: 0)
        if let data = try? JSONEncoder().encode(outfits) {
            UserDefaults.standard.set(data, forKey: kOutfits)
        }
    }

    var currentDollId: String {
        BuiltInCatalog.dolls.first { $0.gender == gender }?.id ?? "doll_female_default"
    }

    // MARK: - 远端目录（GET /api/clothes 合并）

    func fetchRemoteCatalog() async {
        guard apiBase.hasPrefix("http") else { return }
        do {
            let items: [ClothItem] = try await APIClient.shared.get(
                apiBase + "/api/clothes", token: authToken)
            guard !items.isEmpty else { return }
            var merged = BuiltInCatalog.clothes
            for it in items where !merged.contains(where: { $0.id == it.id }) {
                merged.append(it)
            }
            catalog = merged
            remoteCatalogLoaded = true
        } catch {
            loadError = "后端目录不可用（已使用内置示例目录）：\(error.localizedDescription)"
        }
    }

    func itemById(_ id: String) -> ClothItem? {
        catalog.first { $0.id == id }
    }
}
