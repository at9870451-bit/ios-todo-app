package com.quantokx.model;

import java.util.List;

/**
 * K 线。契约：{ "ts": 1700000000000, "open":68000, "high":68100, "low":67900, "close":68050, "vol":12.3 }
 * ts 为毫秒时间戳；列表按「旧 → 新」排序（前端画图/算指标依赖该顺序）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> struct Candle（init?(raw:)）
 */
public record Candle(long ts, double open, double high, double low, double close, double vol) {

    /**
     * OKX /api/v5/market/candles 返回的单行原始数组：
     * [ts, o, h, l, c, vol, volCcy, volCcyQuote, confirm]
     * 解析失败（元素不足或非数字）返回 null，与 iOS 的 init? 语义一致。
     */
    public static Candle fromOkx(List<String> raw) {
        if (raw == null || raw.size() < 6) {
            return null;
        }
        try {
            long ts = (long) Double.parseDouble(raw.get(0));
            double open = Double.parseDouble(raw.get(1));
            double high = Double.parseDouble(raw.get(2));
            double low = Double.parseDouble(raw.get(3));
            double close = Double.parseDouble(raw.get(4));
            double vol = Double.parseDouble(raw.get(5));
            return new Candle(ts, open, high, low, close, vol);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
