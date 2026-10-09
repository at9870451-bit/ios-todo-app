package com.quantokx.model;

/**
 * 策略输出信号（纯计算结果，不含任何网络/下单行为）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Models/Models.swift -> struct Signal
 *
 * @param action     动作
 * @param reason     人类可读理由（前端日志与 AI 摘要都会展示）
 * @param confidence 置信度 0..1（hold 时为 0，与 iOS 一致）
 * @param strategy   产生该信号的策略
 * @param price      信号产生时的价格
 */
public record Signal(SignalAction action, String reason, double confidence, StrategyKind strategy, double price) {

    /** 观望信号：confidence 固定 0，与 iOS 的 Signal.hold 一致 */
    public static Signal hold(String reason, StrategyKind strategy, double price) {
        return new Signal(SignalAction.HOLD, reason, 0, strategy, price);
    }
}
