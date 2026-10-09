package com.quantokx.model;

import com.fasterxml.jackson.annotation.JsonValue;

/**
 * 信号动作。wire 值与 iOS 端 SignalAction 的 rawValue 一致（契约 lastSignal.action 只可能是这 5 个值）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> enum SignalAction
 */
public enum SignalAction {

    BUY("buy", "开多"),
    SELL("sell", "开空"),
    HOLD("hold", "观望"),
    CLOSE_LONG("closeLong", "平多"),
    CLOSE_SHORT("closeShort", "平空");

    private final String wire;
    private final String label;

    SignalAction(String wire, String label) {
        this.wire = wire;
        this.label = label;
    }

    @JsonValue
    public String wire() {
        return wire;
    }

    /** 中文动作名（trade log 的 action 字段、AI 回复展示用） */
    public String label() {
        return label;
    }

    /** 是否是需要真正下单的动作（hold 不是） */
    public boolean isAction() {
        return this != HOLD;
    }

    public static SignalAction fromWireOrNull(String wire) {
        if (wire == null) {
            return null;
        }
        for (SignalAction a : values()) {
            if (a.wire.equals(wire)) {
                return a;
            }
        }
        return null;
    }
}
