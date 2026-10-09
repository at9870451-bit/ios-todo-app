package com.quantokx.model;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * 策略类型。wire 值与 iOS 端 StrategyKind 的 rawValue 完全一致（契约：grid / maCross / rsi / breakout / ai）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> enum StrategyKind
 */
public enum StrategyKind {

    GRID("grid", "网格交易", "在区间内低买高卖，震荡行情收益稳定"),
    MA_CROSS("maCross", "均线交叉", "快线上穿慢线开多，下穿开空，适合趋势"),
    RSI("rsi", "RSI 反转", "RSI < 30 超卖买入，> 70 超买卖出"),
    BREAKOUT("breakout", "通道突破", "突破 N 周期高点做多，跌破低点做空"),
    AI("ai", "AI 自主决策", "把行情和技术指标交给 AI，由它决定买卖");

    private final String wire;
    private final String title;
    private final String detail;

    StrategyKind(String wire, String title, String detail) {
        this.wire = wire;
        this.title = title;
        this.detail = detail;
    }

    /** JSON 序列化时使用的值（config.json 持久化 / REST 响应） */
    @JsonValue
    public String wire() {
        return wire;
    }

    public String title() {
        return title;
    }

    public String detail() {
        return detail;
    }

    /** 未知值抛 IllegalArgumentException（用于 @JsonCreator 反序列化配置文件的场景） */
    @JsonCreator
    public static StrategyKind fromWire(String wire) {
        StrategyKind k = fromWireOrNull(wire);
        if (k == null) {
            throw new IllegalArgumentException("未知策略: " + wire);
        }
        return k;
    }

    /** 未知值返回 null（用于接口参数校验，便于给出友好的中文错误信息） */
    public static StrategyKind fromWireOrNull(String wire) {
        if (wire == null) {
            return null;
        }
        for (StrategyKind k : values()) {
            if (k.wire.equals(wire)) {
                return k;
            }
        }
        return null;
    }
}
