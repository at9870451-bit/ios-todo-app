package com.quantokx.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * 账户余额明细（OKX /api/v5/account/balance 的 details[] 元素）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> struct Balance
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record Balance(String ccy, String availBal, String frozenBal, String eq) {

    public double availDouble() {
        return Ticker.parse(availBal);
    }
}
