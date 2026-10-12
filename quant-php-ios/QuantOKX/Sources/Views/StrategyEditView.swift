import SwiftUI

/// 策略创建 / 编辑表单（动态参数由 /api/strategy/meta 驱动）
struct StrategyEditView: View {
    @EnvironmentObject var store: BackendStore

    /// 编辑已有策略时传入，创建时 nil
    var existing: StrategyRow? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var className = "ma"
    @State private var marketType = "swap"
    @State private var directionMode = "long_only"
    @State private var symbol = "BTC-USDT-SWAP"
    @State private var symbolList: [String] = ["BTC-USDT-SWAP"]
    @State private var interval = "15m"
    @State private var mode = "paper"
    @State private var positionPercent = "5"
    @State private var leverage = "1"
    @State private var minConfidence = "0.6"
    @State private var quantity = "0.001"
    @State private var tdMode = "cross"
    @State private var paramValues: [String: String] = [:]
    @State private var saving = false
    @State private var loaded = false

    private let intervals = ["1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "6h", "12h", "1d"]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(uiColor: .systemGroupedBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(existing == nil ? "创建策略" : "编辑策略")
                        .font(.headline).foregroundStyle(.primary)
                        .padding(.top, 8)

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            FieldRow(icon: "tag.fill", placeholder: "策略名称", text: $name)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("策略类型").font(.caption).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(metaKeys, id: \.self) { key in
                                            Button {
                                                className = key
                                                resetParams()
                                            } label: {
                                                Text(metaName(key))
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(className == key ? .white : .secondary)
                                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                                    .background(className == key ? Color.blue : Color(uiColor: .systemGray6),
                                                                in: Capsule())
                                            }
                                        }
                                    }
                                }
                                if let desc = store.strategyMeta?.strategies[className]?.desc {
                                    Text(desc).font(.caption2).foregroundStyle(.secondary)
                                }
                            }

                            Picker("市场", selection: $marketType) {
                                Text("永续 Swap").tag("swap")
                                Text("现货 Spot").tag("spot")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: marketType) { _, _ in
                                adjustSymbol()
                            }

                            Picker("方向", selection: $directionMode) {
                                Text("只做多").tag("long_only")
                                Text("只做空").tag("short_only")
                                Text("多空双向").tag("long_short")
                            }
                            .pickerStyle(.segmented)

                            MultiSymbolEditor(title: "自动交易币种（多选，逐个分析执行）", symbols: $symbolList)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("K 线周期").font(.caption).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(intervals, id: \.self) { i in
                                            Button {
                                                interval = i
                                            } label: {
                                                Text(i)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(interval == i ? .white : .secondary)
                                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                                    .background(interval == i ? Color.blue : Color(uiColor: .systemGray6),
                                                                in: Capsule())
                                            }
                                        }
                                    }
                                }
                            }

                            Picker("模式", selection: $mode) {
                                Text("本地模拟").tag("paper")
                                Text("OKX 模拟盘").tag("testnet")
                                Text("实盘").tag("live")
                            }
                            .pickerStyle(.segmented)

                            HStack(spacing: 10) {
                                FieldRow(icon: "percent", placeholder: "仓位 %", text: $positionPercent)
                                    .keyboardType(.decimalPad)
                                if marketType == "swap" {
                                    FieldRow(icon: "gauge.with.dots.needle.67percent", placeholder: "杠杆", text: $leverage)
                                        .keyboardType(.numberPad)
                                }
                            }

                            HStack(spacing: 10) {
                                FieldRow(icon: "number", placeholder: "下单数量", text: $quantity)
                                    .keyboardType(.decimalPad)
                                FieldRow(icon: "dial.medium", placeholder: "最低置信度 0-1", text: $minConfidence)
                                    .keyboardType(.decimalPad)
                            }

                            if marketType == "swap" {
                                Picker("保证金模式", selection: $tdMode) {
                                    Text("全仓 cross").tag("cross")
                                    Text("逐仓 isolated").tag("isolated")
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }

                    // 策略参数（动态）
                    if let params = store.strategyMeta?.strategies[className]?.params, !params.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("策略参数").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                ForEach(params) { p in
                                    HStack {
                                        Text(p.label).font(.footnote).foregroundStyle(.secondary)
                                            .frame(width: 130, alignment: .leading)
                                        TextField("", text: Binding(
                                            get: { paramValues[p.key] ?? p.defaultValue?.value ?? "" },
                                            set: { paramValues[p.key] = $0 }
                                        ))
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.trailing)
                                        .keyboardType(.numbersAndPunctuation)
                                    }
                                    .padding(10)
                                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                        }
                    }

                    PrimaryButton(title: saving ? "保存中…" : (existing == nil ? "创建策略" : "保存修改"),
                                  icon: "checkmark.circle.fill", disabled: saving) {
                        Task { await save() }
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("取消").font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(existing == nil ? "创建策略" : "编辑策略")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadStrategyMeta()
            fill()
        }
    }

    private var metaKeys: [String] {
        Array(store.strategyMeta?.strategies.keys.map { $0 } ?? []).sorted()
    }

    private func metaName(_ key: String) -> String {
        store.strategyMeta?.strategies[key]?.name ?? key.uppercased()
    }

    private func resetParams() {
        paramValues = [:]
        if let params = store.strategyMeta?.strategies[className]?.params {
            for p in params {
                if let d = p.defaultValue?.value { paramValues[p.key] = d }
            }
        }
    }

    private func adjustSymbol() {
        let base: String = {
            if symbol.contains("-SWAP") { return symbol.replacingOccurrences(of: "-SWAP", with: "") }
            return symbol
        }()
        symbol = marketType == "swap" ? (base.contains("-") ? base + "-SWAP" : base) : base
    }

    private func fill() {
        guard !loaded else { return }
        resetParams()
        if let e = existing {
            name = e.name
            className = e.className
            marketType = e.marketType
            directionMode = e.directionMode
            symbol = e.symbol
            interval = e.interval
            mode = e.mode
            positionPercent = String(format: "%.0f", e.positionPercent)
            leverage = "\(e.leverage)"
            minConfidence = String(format: "%.2f", e.minConfidence)
        }
        symbolList = symbol.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        loaded = true
    }

    private func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            store.toast = "请填写策略名称"
            return
        }
        saving = true
        defer { saving = false }
        var body: [String: Any] = [
            "name": name,
            "class_name": className,
            "market_type": marketType,
            "direction_mode": directionMode,
            "symbol": (symbolList.first ?? "BTC-USDT-SWAP").uppercased(),
            "symbols": symbolList.map { $0.uppercased() }.joined(separator: ","),
            "interval": interval,
            "mode": mode,
            "position_percent": positionPercent,
            "leverage": Int(leverage) ?? 1,
            "min_confidence": minConfidence,
            "quantity": quantity,
            "td_mode": tdMode,
            "parameters": paramValues,
        ]
        if let e = existing { body["id"] = e.id }
        if await store.saveStrategy(body) {
            dismiss()
        }
    }
}

/// AI 配置创建 / 编辑表单
struct AiConfigEditView: View {
    @EnvironmentObject var store: BackendStore

    var existingId: Int? = nil      // 编辑时传入 id
    var isFreeAi: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var name = "默认 AI"
    @State private var providerType = "openai"
    @State private var apiUrl = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var temperature = "0.2"
    @State private var maxTokens = "800"
    @State private var mode = "auto"
    @State private var enabled = true
    @State private var tradeMode = "demo"
    @State private var leverage = "1"
    @State private var autoSymbols: [String] = ["BTC-USDT-SWAP"]
    @State private var autoMarketType = "swap"
    @State private var directionMode = "long_only"
    @State private var autoInterval = "15m"
    @State private var autoPeriodSeconds = "300"
    @State private var autoQuantity = "0.001"
    @State private var autoPositionPercent = "2"
    @State private var capitalUsdt = "0"
    @State private var minConfidence = "0.6"
    @State private var strategyNote = ""
    @State private var saving = false
    @State private var loaded = false
    @State private var testMsg = ""

    private let intervals = ["1m", "5m", "15m", "30m", "1h", "4h", "1d"]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.0), Color(uiColor: .systemGroupedBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(existingId == nil ? "新建 AI 配置" : "编辑 AI 配置")
                        .font(.headline).foregroundStyle(.primary)
                        .padding(.top, 8)

                    // 模型设置
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("模型").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            FieldRow(icon: "tag.fill", placeholder: "配置名称", text: $name)
                            Picker("提供商", selection: $providerType) {
                                Text("OpenAI").tag("openai")
                                Text("Azure").tag("azure")
                                Text("Claude").tag("claude")
                                Text("Gemini").tag("gemini")
                                Text("自定义").tag("custom")
                            }
                            .pickerStyle(.menu).tint(.white)
                            FieldRow(icon: "cpu", placeholder: "模型名，如 gpt-4o-mini", text: $model)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            FieldRow(icon: "link", placeholder: "API 地址（留空用默认）", text: $apiUrl)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            SecureFieldRow(icon: "key.fill", placeholder: existingId == nil ? "API Key" : "API Key（留空保持原值）", text: $apiKey)
                            HStack(spacing: 10) {
                                FieldRow(icon: "thermometer", placeholder: "温度", text: $temperature).keyboardType(.decimalPad)
                                FieldRow(icon: "textformat.size", placeholder: "最大 tokens", text: $maxTokens).keyboardType(.numberPad)
                            }
                        }
                    }

                    // 运行设置
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("运行").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            HStack {
                                Text("模式").font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                                StatusBadge(text: "自动交易（服务端统一）", color: .purple)
                            }
                            HStack {
                                Text("启用").font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                                Toggle("", isOn: $enabled).tint(.green).labelsHidden()
                            }
                            Text("分析/确认模式请直接用 OKX 页的「AI 分析」或策略回测；本配置用于自动交易。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    // 自动交易
                    Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("自动交易").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)

                                Picker("交易环境", selection: $tradeMode) {
                                    Text("模拟盘 Demo").tag("demo")
                                    Text("实盘 Live").tag("live")
                                }
                                .pickerStyle(.segmented)

                                Picker("市场", selection: $autoMarketType) {
                                    Text("永续").tag("swap")
                                    Text("现货").tag("spot")
                                }
                                .pickerStyle(.segmented)

                                MultiSymbolEditor(title: "自动交易币种（多选，逐个分析执行）", symbols: $autoSymbols)
                                    .textInputAutocapitalization(.characters).autocorrectionDisabled()

                                Picker("方向", selection: $directionMode) {
                                    Text("只做多").tag("long_only")
                                    Text("只做空").tag("short_only")
                                    Text("双向").tag("long_short")
                                }
                                .pickerStyle(.segmented)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("K 线周期").font(.caption).foregroundStyle(.secondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(intervals, id: \.self) { i in
                                                Button {
                                                    autoInterval = i
                                                } label: {
                                                    Text(i)
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(autoInterval == i ? .white : .secondary)
                                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                                        .background(autoInterval == i ? Color.purple.opacity(0.6) : Color(uiColor: .systemGray6),
                                                                    in: Capsule())
                                                }
                                            }
                                        }
                                    }
                                }

                                HStack(spacing: 10) {
                                    FieldRow(icon: "timer", placeholder: "轮询秒", text: $autoPeriodSeconds).keyboardType(.numberPad)
                                    FieldRow(icon: "gauge.with.dots.needle.67percent", placeholder: "杠杆", text: $leverage).keyboardType(.numberPad)
                                }
                                HStack(spacing: 10) {
                                    FieldRow(icon: "number", placeholder: "下单数量", text: $autoQuantity).keyboardType(.decimalPad)
                                    FieldRow(icon: "percent", placeholder: "仓位 %", text: $autoPositionPercent).keyboardType(.decimalPad)
                                }
                                HStack(spacing: 10) {
                                    FieldRow(icon: "dollarsign.circle", placeholder: "资金规模 USDT", text: $capitalUsdt).keyboardType(.decimalPad)
                                    FieldRow(icon: "dial.medium", placeholder: "最低置信度", text: $minConfidence).keyboardType(.decimalPad)
                                }

                                FieldRow(icon: "text.bubble", placeholder: "策略提示词补充（可选）", text: $strategyNote)
                            }
                        }

                    if !testMsg.isEmpty {
                        Card(padding: 12) {
                            Text(testMsg).font(.caption).foregroundStyle(.primary)
                        }
                    }

                    PrimaryButton(title: saving ? "保存中…" : "保存配置", icon: "checkmark.circle.fill", disabled: saving) {
                        Task { await save() }
                    }

                    if let id = existingId, id > 0, !isFreeAi {
                        PrimaryButton(title: "测试连接", icon: "antenna.radiowaves.left.and.right",
                                      color: Color.green) {
                            Task { testMsg = await store.testAiConfig(id: id) }
                        }
                        PrimaryButton(title: "删除配置", icon: "trash.fill", color: Color.red) {
                            Task {
                                if await store.deleteAiConfig(id: id) { dismiss() }
                            }
                        }
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("取消").font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(existingId == nil ? "新建 AI 配置" : "编辑 AI 配置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = existingId, id > 0, !isFreeAi {
                if let d = await store.loadAiConfig(id: id) {
                    fillFrom(d)
                }
            }
            loaded = true
        }
    }

    private func fillFrom(_ d: AiConfigDetail) {
        guard !loaded else { return }
        name = d.name
        providerType = d.providerType ?? "openai"
        apiUrl = d.apiUrl ?? ""
        model = d.model ?? ""
        temperature = String(format: "%.1f", d.temperature ?? 0.2)
        maxTokens = "\(d.maxTokens ?? 800)"
        mode = d.mode
        enabled = d.enabled
        tradeMode = d.tradeMode ?? "demo"
        leverage = "\(d.leverage ?? 1)"
        autoSymbols = ((d.autoSymbols ?? "").isEmpty ? (d.autoSymbol ?? "BTC-USDT-SWAP") : d.autoSymbols!)
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        autoMarketType = d.autoMarketType ?? "swap"
        directionMode = d.directionMode ?? "long_only"
        autoInterval = d.autoInterval ?? "15m"
        autoPeriodSeconds = "\(d.autoPeriodSeconds ?? 300)"
        autoQuantity = d.autoQuantity ?? "0.001"
        autoPositionPercent = String(format: "%.1f", d.autoPositionPercent ?? 2)
        capitalUsdt = String(format: "%.0f", d.capitalUsdt ?? 0)
        minConfidence = String(format: "%.2f", d.minConfidence ?? 0.6)
        strategyNote = d.strategyNote ?? ""
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: Any] = [
            "name": name,
            "provider_type": providerType,
            "model": model,
            "temperature": temperature,
            "max_tokens": Int(maxTokens) ?? 800,
            "mode": mode,
            "enabled": enabled ? 1 : 0,
        ]
        if !apiUrl.isEmpty { body["api_url"] = apiUrl }
        if !apiKey.isEmpty { body["api_key"] = apiKey }
        if let id = existingId { body["id"] = id }

        if mode == "auto" {
            body["trade_mode"] = tradeMode
            body["leverage"] = Int(leverage) ?? 1
            body["auto_symbol"] = (autoSymbols.first ?? "BTC-USDT-SWAP").uppercased()
            body["auto_symbols"] = autoSymbols.map { $0.uppercased() }.joined(separator: ","),
            body["auto_market_type"] = autoMarketType
            body["direction_mode"] = directionMode
            body["auto_interval"] = autoInterval
            body["auto_period_seconds"] = Int(autoPeriodSeconds) ?? 300
            body["auto_quantity"] = autoQuantity
            body["auto_position_percent"] = autoPositionPercent
            body["capital_usdt"] = capitalUsdt
            body["min_confidence"] = minConfidence
            if !strategyNote.isEmpty { body["strategy_note"] = strategyNote }
        }

        if await store.saveAiConfig(body) {
            dismiss()
        }
    }
}
