package com.quantokx.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * 未成交委托（OKX /api/v5/trade/orders-pending 元素）。
 * 契约 GET /api/orders → { "ordId","instId","side","ordType","sz","px","state" }
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record OpenOrder(String ordId,
                        String instId,
                        String side,
                        String ordType,
                        String sz,
                        String px,
                        String state) {
}
