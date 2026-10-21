// DollStudio3D — 辅助：从 entry 提取动画 key（ObjC 桥接下类型不定）
import Foundation

func entryValueKey(_ entry: Any) -> String? {
    if let s = entry as? String { return s }
    if let o = (entry as? NSObject)?.value(forKey: "identifier") as? String { return o }
    return nil
}
