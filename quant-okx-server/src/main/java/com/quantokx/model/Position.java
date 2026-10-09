package com.quantokx.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * 持仓。数值都是 OKX 原始字符串（契约：前端自行 parse）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> struct Position
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record Position(String instId,
                       String posSide,
                       String pos,
                       String avgPx,
                       String upl,
                       String uplRatio,
                       String lever,
                       String mgnMode) {

    public double posDouble() {
        return Ticker.parse(pos);
    }

    public double avgDouble() {
        return Ticker.parse(avgPx);
    }

    public double uplDouble() {
        return Ticker.parse(upl);
    }

    public double uplRatioDouble() {
        return Ticker.parse(uplRatio);
    }

    /** long 持仓（单向持仓模式下 net 且 pos > 0） */
    public boolean isLong() {
        return "long".equals(posSide) || ("net".equals(posSide) && posDouble() > 0);
    }

    /** short 持仓（单向持仓模式下 net 且 pos < 0） */
    public boolean isShort() {
        return "short".equals(posSide) || ("net".equals(posSide) && posDouble() < 0);
    }

    /** 与 iOS 一致：|pos| < 1e-7 视为空仓 */
    public boolean isEmpty() {
        return Math.abs(posDouble()) < 0.0000001;
    }
}
