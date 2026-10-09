package com.quantokx.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * 下单返回（OKX /api/v5/trade/order 的 data[0]）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> struct OrderResult
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record OrderResult(String ordId, String clOrdId, String sCode, String sMsg) {

    public boolean ok() {
        return "0".equals(sCode);
    }
}
