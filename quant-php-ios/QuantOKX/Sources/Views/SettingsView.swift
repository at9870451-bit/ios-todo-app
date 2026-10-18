import SwiftUI

/// 设置页：以原生导航栏为骨架，内容使用白色分组卡片与 Liquid Glass。
struct VoiceSettingsCard: View {
    @EnvironmentObject var store: BackendStore
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var ps: ProviderStore
    @EnvironmentObject var bg: BackgroundStore
    @AppStorage("tts.engine") private var ttsEngine = "local"
    @AppStorage("tts.personaMatch") private var personaMatchVoice = true
    @AppStorage("tts.providerId") private var ttsProviderId = ""
    @AppStorage("tts.serverVoice") private var serverVoice = "huayan_fast"
    @AppStorage("tts.siliconflow.voice") private var sfVoice = SiliconFlowTTS.defaultVoiceID
    @AppStorage("tts.doubao.voice") private var dbVoice = DoubaoTTS.defaultVoiceID
    // 云端供应商密钥（存 UserDefaults，设置页可编辑）
    @State private var sfKey = UserDefaults.standard.string(forKey: "tts.siliconflow.key") ?? ""
    @State private var dbAppID = UserDefaults.standard.string(forKey: "tts.doubao.appid") ?? ""
    @State private var dbToken = UserDefaults.standard.string(forKey: "tts.doubao.token") ?? ""
    // 播放调节（音量倍数 / 语速倍数 / 合成增益）
    @State private var playVolume = UserDefaults.standard.object(forKey: "tts.playback.volume") as? Float ?? 1.0
    @State private var playSpeed = UserDefaults.standard.object(forKey: "tts.playback.speed") as? Float ?? 1.0
    @State private var serverGain = UserDefaults.standard.integer(forKey: "tts.server.gain")

    /// 可嵌入「我的」页的朗读设置卡（含引擎/音色/密钥/调节器/版本行）
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceL) {
            personalizationCard
            speechCard
            versionCard
        }
    }

    private var personalizationCard: some View {
        VStack(spacing: 0) {
            settingLink(icon: "cpu", title: "AI 模型配置", subtitle: subtitleForProviders) {
                ProviderListView()
            }

            rowDivider
            settingLink(icon: "paintbrush", title: "外观", subtitle: bg.image == nil ? "苹果白与蓝橙渐变" : "自定义背景图片") {
                AppearanceView()
            }
        }
        .glassPanel(Theme.radiusL)
    }

    private var speechCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeading(icon: "speaker.wave.2", title: "朗读")
            HStack(spacing: 12) {
                SquircleIcon(system: "iphone", size: 38, tinted: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("朗读引擎")
                        .font(.subheadline.weight(.semibold))
                    Text(ttsEngine == "local" ? "使用设备内置语音"
                         : ttsEngine == "server" ? "自建开源神经音色"
                         : ttsEngine == "cloud_sf" ? "硅基流动云端音色"
                         : ttsEngine == "cloud_doubao" ? "豆包云端音色"
                         : "使用已配置的语音模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("朗读引擎", selection: $ttsEngine) {
                    Text("本地语音").tag("local")
                    Text("开源语音库").tag("server")
                    Text("硅基流动").tag("cloud_sf")
                    Text("豆包").tag("cloud_doubao")
                    Text("语音模型").tag("model")
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, 12)

            if ttsEngine == "cloud_sf" {
                rowDivider.padding(.leading, 62)
                HStack(spacing: 12) {
                    SquircleIcon(system: "sparkles", size: 38, tinted: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("音色")
                            .font(.subheadline.weight(.semibold))
                        Text(sfVoiceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Picker("音色", selection: $sfVoice) {
                        ForEach(SiliconFlowTTS.voices) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    .disabled(personaMatchVoice)
                    .opacity(personaMatchVoice ? 0.45 : 1)
                }
                .padding(.horizontal, Theme.cardPadding)
                .padding(.vertical, 10)
                HStack(spacing: 10) {
                    TextField("硅基流动 API Key（sk-…）", text: $sfKey)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        UserDefaults.standard.set(sfKey, forKey: "tts.siliconflow.key")
                        Haptics.success()
                        store.toast = "已保存"
                    } label: {
                        Text("保存")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
                .padding(.horizontal, Theme.cardPadding)
                .padding(.bottom, Theme.cardPadding)
            } else if ttsEngine == "cloud_doubao" {
                rowDivider.padding(.leading, 62)
                HStack(spacing: 12) {
                    SquircleIcon(system: "waveform.circle", size: 38, tinted: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("音色")
                            .font(.subheadline.weight(.semibold))
                        Text(dbVoiceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Picker("音色", selection: $dbVoice) {
                        ForEach(DoubaoTTS.voices) { v in
                            Text(v.name).tag(v.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    .disabled(personaMatchVoice)
                    .opacity(personaMatchVoice ? 0.45 : 1)
                }
                .padding(.horizontal, Theme.cardPadding)
                .padding(.vertical, 10)
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        TextField("AppID", text: $dbAppID)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            UserDefaults.standard.set(dbAppID, forKey: "tts.doubao.appid")
                            Haptics.success()
                            store.toast = "已保存"
                        } label: {
                            Text("保存")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Divider()
                    HStack(spacing: 10) {
                        SecureField("Access Token", text: $dbToken)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            UserDefaults.standard.set(dbToken, forKey: "tts.doubao.token")
                            Haptics.success()
                            store.toast = "已保存"
                        } label: {
                            Text("保存")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
                .padding(.horizontal, Theme.cardPadding)
                .padding(.bottom, Theme.cardPadding)
            } else if ttsEngine == "server" {
                rowDivider.padding(.leading, 62)
                HStack(spacing: 12) {
                    SquircleIcon(system: "waveform.badge.magnifyingglass", size: 38, tinted: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("音色")
                            .font(.subheadline.weight(.semibold))
                        Text(serverVoiceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Picker("音色", selection: $serverVoice) {
                        Text("华严·极速").tag("huayan_fast")
                        Text("华严·高清").tag("huayan")
                        Text("沧元·男声").tag("chaowen")
                        Text("小雅·女声").tag("xiaoya")
                        Text("特蕾莎·女声").tag("theresa")
                        Text("特蕾莎·声线2").tag("theresa2")
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    .disabled(personaMatchVoice)
                    .opacity(personaMatchVoice ? 0.45 : 1)
                }
                .padding(.horizontal, Theme.cardPadding)
                .padding(.vertical, 10)
            } else if ttsEngine == "model" {
                rowDivider.padding(.leading, 62)
                if ttsProviders.isEmpty {
                    settingLink(icon: "waveform.badge.plus", title: "选择语音模型", subtitle: "尚未添加语音模型 · 点此前往添加") {
                        ProviderListView()
                    }
                } else {
                    HStack(spacing: 12) {
                        SquircleIcon(system: "waveform", size: 38, tinted: true)
                        Picker("语音模型", selection: $ttsProviderId) {
                            ForEach(ttsProviders) { p in
                                Text("\(p.label) · \(p.model.isEmpty ? "tts-1" : p.model)").tag(p.id.uuidString)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.cardPadding)
                    .padding(.vertical, 10)
                }
            }

            // 播放调节：音量倍数 / 语速倍数 / 合成增益（收进音色卡片内）
            rowDivider
            HStack(spacing: 12) {
                SquircleIcon(system: "speaker.wave.3", size: 38, tinted: true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("音量倍数")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "×%.1f", playVolume))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .monospacedDigit()
                    }
                    Slider(value: $playVolume, in: 0.2...2.0, step: 0.1) { _ in
                        UserDefaults.standard.set(Float(playVolume), forKey: "tts.playback.volume")
                    }
                    .tint(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, 10)
            rowDivider
            HStack(spacing: 12) {
                SquircleIcon(system: "gauge.with.needle", size: 38, tinted: true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("语速倍数")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "×%.1f", playSpeed))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .monospacedDigit()
                    }
                    Slider(value: $playSpeed, in: 0.5...2.0, step: 0.1) { _ in
                        UserDefaults.standard.set(Float(playSpeed), forKey: "tts.playback.speed")
                    }
                    .tint(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, 10)
            if ttsEngine == "server" {
                rowDivider
                HStack(spacing: 12) {
                    SquircleIcon(system: "waveform.badge.plus", size: 38, tinted: true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("合成增益")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(serverGain) dB")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(serverGain) },
                            set: { v in
                                serverGain = Int(v)
                                UserDefaults.standard.set(serverGain, forKey: "tts.server.gain")
                            }
                        ), in: -10...10, step: 1)
                        .tint(Theme.accent)
                        Text("服务器合成时整体响度（Piper 系音色）")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, Theme.cardPadding)
                .padding(.vertical, 10)
            }

            Text(engineHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.cardPadding)
                .padding(.bottom, Theme.cardPadding)

            // 人设音色匹配
            rowDivider
            HStack(spacing: 12) {
                SquircleIcon(system: "person.text.rectangle", size: 38, tinted: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("按人设匹配音色")
                        .font(.subheadline.weight(.semibold))
                    Text(personaMatchHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $personaMatchVoice)
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, 10)
        }
        .glassPanel(Theme.radiusL)
    }

    private var versionCard: some View {
        HStack(spacing: 12) {
            SquircleIcon(system: "app.badge.fill", size: 38, tinted: true)
            Text("版本")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(Self.versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.cardPadding)
        .glassPanel(Theme.radiusL)
    }

    private func cardHeading(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.subheadline.weight(.bold))
            Spacer()
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.top, Theme.cardPadding)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func settingLink<Destination: View>(icon: String, title: String, subtitle: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                SquircleIcon(system: icon, size: 38, tinted: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.62))
            .frame(height: 0.8)
    }

    private var serverVoiceName: String {
        switch serverVoice {
        case "huayan": return "华严 · 高清女声"
        case "chaowen": return "沧元 · 男声"
        case "xiaoya": return "小雅 · 女声"
        case "theresa": return "特蕾莎 · 女声（VITS）"
        case "theresa2": return "特蕾莎 · 女声 · 声线2"
        default: return "华严 · 极速女声"
        }
    }

    private var sfVoiceName: String {
        SiliconFlowTTS.voices.first { $0.id == sfVoice }?.name ?? "Anna · 沉稳女声"
    }

    private var dbVoiceName: String {
        DoubaoTTS.voices.first { $0.id == dbVoice }?.name ?? "灿灿 · 通用女声"
    }

    private var personaMatchHint: String {
        let gender = PersonaVoice.gender
        let genderText = gender == "female" ? "女性" : (gender == "male" ? "男性" : "未指定性别")
        let ageText = PersonaVoice.age > 0 ? "、\(PersonaVoice.age) 岁" : ""
        if personaMatchVoice {
            switch gender {
            case "female", "male":
                return "已按人设（\(genderText)\(ageText)）自动匹配音色与语速（女性→女声、男性→男声）；下方手动音色已停用"
            default:
                return "已开启人设匹配：请先到「人设」设置性别年龄；下方手动音色已停用"
            }
        }
        return "未开启：使用下方手动选择的音色（开启后按人设性别/年龄/性格自动匹配）"
    }

    private var engineHint: String {
        switch ttsEngine {
        case "server": return "自建开源语音库（Piper · MIT）：服务器热态合成、免密钥；首次用新音色约需数秒预热"
        case "cloud_sf": return "硅基流动（SiliconFlow）云端音色：需注册获取 API Key（有免费额度），8 款中文音色"
        case "cloud_doubao": return "豆包（火山引擎）精品音色：需在火山引擎控制台开通语音合成并获取 AppID/Token"
        case "model": return "朗读将调用所选语音模型合成（需支持 /v1/audio/speech）"
        default: return "使用设备内置语音离线朗读，无需网络"
        }
    }

    private var ttsProviders: [ProviderStore.Provider] {
        ps.providers.filter { $0.kind == .tts && !$0.apiKey.isEmpty }
    }

    private var subtitleForProviders: String {
        if let a = ps.active { return "使用中 · \(a.label)" }
        return ps.providers.isEmpty ? "未添加 · 点进去配置" : "\(ps.providers.count) 个模型"
    }

    private static var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.9"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "31"
        return "v\(v) (\(b))"
    }
}
