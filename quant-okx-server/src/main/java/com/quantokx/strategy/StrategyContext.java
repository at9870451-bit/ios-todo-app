package com.quantokx.strategy;

import com.quantokx.model.Candle;
import com.quantokx.model.Ticker;

import java.util.List;

/**
 * 策略评估所需的上下文（纯数据，不碰网络和下单 —— 便于离线回测）。
 * 对照：quant-okx-ios/QuantOKX/Sources/Strategy/StrategyEngine.swift -> struct StrategyContext
 *
 * @param instId   交易对
 * @param candles  K 线（旧 → 新）
 * @param ticker   当前行情
 * @param hasLong  是否持多
 * @param hasShort 是否持空
 * @param params   策略参数
 */
public record StrategyContext(String instId,
                              List<Candle> candles,
                              Ticker ticker,
                              boolean hasLong,
                              boolean hasShort,
                              Params params) {

    /** 收盘价序列（与 Swift 的 var closes 计算属性一致，每次重新计算） */
    public List<Double> closes() {
        return candles.stream().map(Candle::close).toList();
    }

    /** 最新价 */
    public double price() {
        return ticker.lastDouble();
    }

    /**
     * 策略参数。前两个来自用户配置，其余使用与 iOS 端完全一致的默认值。
     * 对照 Swift: struct Params（fastMA=7, slowMA=25, rsiPeriod=14, rsiLow=30,
     * rsiHigh=70, breakoutLookback=20, gridLevels=10, gridRangePct=3.0）
     */
    public record Params(double stopLossPct,
                         double takeProfitPct,
                         int fastMA,
                         int slowMA,
                         int rsiPeriod,
                         double rsiLow,
                         double rsiHigh,
                         int breakoutLookback,
                         int gridLevels,
                         double gridRangePct) {

        /** 用默认策略参数 + 用户的风控参数构造 */
        public static Params withRisk(double stopLossPct, double takeProfitPct) {
            return new Params(stopLossPct, takeProfitPct, 7, 25, 14, 30, 70, 20, 10, 3.0);
        }
    }
}
