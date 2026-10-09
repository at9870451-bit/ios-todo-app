package com.quantokx.model;

/**
 * 交易日志条目。契约 GET /api/logs →
 * { "id","time","instId","action","price","size","note","success" }
 * time 为 ISO-8601 字符串（如 2026-10-10T04:30:00Z）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> struct TradeLog
 */
public record TradeLogEntry(String id,
                            String time,
                            String instId,
                            String action,
                            double price,
                            double size,
                            String note,
                            boolean success) {
}
