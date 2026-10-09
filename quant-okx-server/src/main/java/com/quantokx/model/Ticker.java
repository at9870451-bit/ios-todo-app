package com.quantokx.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * OKX 行情 ticker（字段为 OKX 原始字符串格式，与 iOS 端 Ticker 一致）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> struct Ticker
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record Ticker(String instId,
                     String last,
                     String open24h,
                     String high24h,
                     String low24h,
                     String vol24h) {

    public double lastDouble() {
        return parse(last);
    }

    public double openDouble() {
        return parse(open24h);
    }

    public double highDouble() {
        return parse(high24h);
    }

    public double lowDouble() {
        return parse(low24h);
    }

    /** 24h 涨跌幅（%），与 iOS 端 changePct 公式一致 */
    public double changePct() {
        double o = openDouble();
        if (o <= 0) {
            return 0;
        }
        return (lastDouble() - o) / o * 100;
    }

    static double parse(String v) {
        if (v == null || v.isEmpty()) {
            return 0;
        }
        try {
            return Double.parseDouble(v);
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
