package com.quantokx.strategy;

import com.quantokx.indicator.Indicator;
import com.quantokx.model.Candle;
import com.quantokx.model.Signal;
import com.quantokx.model.SignalAction;
import com.quantokx.model.StrategyKind;
import com.quantokx.strategy.StrategyContext.Params;

import java.util.List;
import java.util.Locale;
import java.util.OptionalDouble;

/**
 * 策略引擎：纯计算，不碰网络和下单。
 * <p>
 * 逐行对照 quant-okx-ios/QuantOKX/Sources/Strategy/StrategyEngine.swift 移植，
 * 阈值、判断顺序、文案都保持一致，保证 iOS / Java 两端行为可复现。
 */
public final class StrategyEngine {

    private StrategyEngine() {
    }

    /** 按策略类型分发 */
    public static Signal evaluate(StrategyKind kind, StrategyContext ctx) {
        return switch (kind) {
            case GRID -> grid(ctx);
            case MA_CROSS -> maCross(ctx);
            case RSI -> rsi(ctx);
            case BREAKOUT -> breakout(ctx);
            // AI 策略由 TradingEngine 异步调用 AiClient 处理
            case AI -> Signal.hold("AI 策略需异步调用", StrategyKind.AI, ctx.price());
        };
    }

    // ------------------------------------------------------------------ 网格

    /**
     * 以近期均价为中心，上下各 gridRangePct% 划区间。
     * 价格落到下沿 → 买；上沿 → 卖。持仓时贴边就止盈。
     * 对照 Swift: static func grid(_ ctx: StrategyContext) -> Signal
     */
    public static Signal grid(StrategyContext ctx) {
        Params p = ctx.params();
        if (ctx.candles().size() < 20) {
            return Signal.hold("K线不足", StrategyKind.GRID, ctx.price());
        }
        List<Double> closes = ctx.closes();
        List<Double> recent = closes.subList(Math.max(0, closes.size() - 60), closes.size());
        double center = recent.stream().mapToDouble(Double::doubleValue).sum() / recent.size();
        double half = center * (p.gridRangePct() / 100.0);
        double lower = center - half;
        double upper = center + half;

        double pos = (ctx.price() - lower) / Math.max(upper - lower, 0.0000001); // 0=下沿 1=上沿

        if (ctx.hasLong()) {
            if (ctx.price() >= upper) {
                return new Signal(SignalAction.CLOSE_LONG,
                        "触及网格上沿 " + fmt(upper) + "，止盈", 0.75, StrategyKind.GRID, ctx.price());
            }
            return Signal.hold("持仓中，等待上沿", StrategyKind.GRID, ctx.price());
        }
        if (ctx.hasShort()) {
            if (ctx.price() <= lower) {
                return new Signal(SignalAction.CLOSE_SHORT,
                        "触及网格下沿 " + fmt(lower) + "，止盈", 0.75, StrategyKind.GRID, ctx.price());
            }
            return Signal.hold("持空仓中，等待下沿", StrategyKind.GRID, ctx.price());
        }

        if (pos <= 0.12) {
            return new Signal(SignalAction.BUY,
                    "价格 " + fmt(ctx.price()) + " 贴近网格下沿 " + fmt(lower), 0.7, StrategyKind.GRID, ctx.price());
        }
        if (pos >= 0.88) {
            return new Signal(SignalAction.SELL,
                    "价格 " + fmt(ctx.price()) + " 贴近网格上沿 " + fmt(upper), 0.7, StrategyKind.GRID, ctx.price());
        }
        return Signal.hold("区间中段（" + (int) (pos * 100) + "%），不操作", StrategyKind.GRID, ctx.price());
    }

    // ------------------------------------------------------------------ 均线交叉

    /**
     * 快线上穿慢线开多，下穿开空（反手先平后开）。
     * 对照 Swift: static func maCross(_ ctx: StrategyContext) -> Signal
     */
    public static Signal maCross(StrategyContext ctx) {
        Params p = ctx.params();
        List<Double> closes = ctx.closes();
        if (closes.size() < p.slowMA() + 2) {
            return Signal.hold("K线不足", StrategyKind.MA_CROSS, ctx.price());
        }
        List<Double> fast = Indicator.sma(closes, p.fastMA());
        List<Double> slow = Indicator.sma(closes, p.slowMA());
        if (fast.size() < 2 || slow.size() < 2) {
            return Signal.hold("均线计算失败", StrategyKind.MA_CROSS, ctx.price());
        }

        // 对齐尾部
        double f1 = fast.get(fast.size() - 1);
        double f0 = fast.get(fast.size() - 2);
        double s1 = slow.get(slow.size() - 1);
        double s0 = slow.get(slow.size() - 2);

        boolean crossedUp = f0 <= s0 && f1 > s1;
        boolean crossedDown = f0 >= s0 && f1 < s1;
        boolean above = f1 > s1;

        if (crossedUp) {
            if (ctx.hasShort()) {
                return new Signal(SignalAction.CLOSE_SHORT,
                        "快线上穿慢线，平空反手", 0.8, StrategyKind.MA_CROSS, ctx.price());
            }
            if (!ctx.hasLong()) {
                return new Signal(SignalAction.BUY,
                        "MA" + p.fastMA() + " 上穿 MA" + p.slowMA() + "（" + fmt(f1) + " > " + fmt(s1) + "）",
                        0.8, StrategyKind.MA_CROSS, ctx.price());
            }
        }
        if (crossedDown) {
            if (ctx.hasLong()) {
                return new Signal(SignalAction.CLOSE_LONG,
                        "快线下穿慢线，平多反手", 0.8, StrategyKind.MA_CROSS, ctx.price());
            }
            if (!ctx.hasShort()) {
                return new Signal(SignalAction.SELL,
                        "MA" + p.fastMA() + " 下穿 MA" + p.slowMA() + "（" + fmt(f1) + " < " + fmt(s1) + "）",
                        0.8, StrategyKind.MA_CROSS, ctx.price());
            }
        }
        return Signal.hold(above ? "多头排列，持仓待涨" : "空头排列，观望", StrategyKind.MA_CROSS, ctx.price());
    }

    // ------------------------------------------------------------------ RSI

    /**
     * RSI < 30 超卖买入（持空先平），> 70 超买卖出（持多先平）。
     * 对照 Swift: static func rsi(_ ctx: StrategyContext) -> Signal
     */
    public static Signal rsi(StrategyContext ctx) {
        Params p = ctx.params();
        List<Double> closes = ctx.closes();
        if (closes.size() <= p.rsiPeriod() + 2) {
            return Signal.hold("K线不足", StrategyKind.RSI, ctx.price());
        }
        List<Double> r = Indicator.rsi(closes, p.rsiPeriod());
        if (r.isEmpty()) {
            return Signal.hold("RSI 计算失败", StrategyKind.RSI, ctx.price());
        }
        double last = r.get(r.size() - 1);

        if (last <= p.rsiLow()) {
            if (ctx.hasShort()) {
                return new Signal(SignalAction.CLOSE_SHORT,
                        "RSI " + (int) last + " 超卖，平空", 0.75, StrategyKind.RSI, ctx.price());
            }
            if (!ctx.hasLong()) {
                return new Signal(SignalAction.BUY,
                        "RSI " + (int) last + " ≤ " + (int) p.rsiLow() + " 超卖", 0.75, StrategyKind.RSI, ctx.price());
            }
        }
        if (last >= p.rsiHigh()) {
            if (ctx.hasLong()) {
                return new Signal(SignalAction.CLOSE_LONG,
                        "RSI " + (int) last + " 超买，平多", 0.75, StrategyKind.RSI, ctx.price());
            }
            if (!ctx.hasShort()) {
                return new Signal(SignalAction.SELL,
                        "RSI " + (int) last + " ≥ " + (int) p.rsiHigh() + " 超买", 0.75, StrategyKind.RSI, ctx.price());
            }
        }
        return Signal.hold("RSI " + (int) last + "，处于中性区", StrategyKind.RSI, ctx.price());
    }

    // ------------------------------------------------------------------ 通道突破

    /**
     * 突破前 N 根（不含当前根）最高价做多，跌破最低价做空。
     * 对照 Swift: static func breakout(_ ctx: StrategyContext) -> Signal
     */
    public static Signal breakout(StrategyContext ctx) {
        Params p = ctx.params();
        List<Candle> candles = ctx.candles();
        int lb = p.breakoutLookback();
        if (candles.size() <= lb + 1) {
            return Signal.hold("K线不足", StrategyKind.BREAKOUT, ctx.price());
        }

        // 不含当前这根：等价于 Swift 的 candles.dropLast().suffix(lookback)
        List<Candle> window = candles.subList(candles.size() - 1 - lb, candles.size() - 1);
        OptionalDouble hiOpt = window.stream().mapToDouble(Candle::high).max();
        OptionalDouble loOpt = window.stream().mapToDouble(Candle::low).min();
        if (hiOpt.isEmpty() || loOpt.isEmpty()) {
            return Signal.hold("窗口计算失败", StrategyKind.BREAKOUT, ctx.price());
        }
        double hi = hiOpt.getAsDouble();
        double lo = loOpt.getAsDouble();

        if (ctx.price() > hi) {
            if (ctx.hasShort()) {
                return new Signal(SignalAction.CLOSE_SHORT,
                        "向上突破 " + fmt(hi), 0.7, StrategyKind.BREAKOUT, ctx.price());
            }
            if (!ctx.hasLong()) {
                return new Signal(SignalAction.BUY,
                        "突破 " + lb + " 周期高点 " + fmt(hi), 0.7, StrategyKind.BREAKOUT, ctx.price());
            }
        }
        if (ctx.price() < lo) {
            if (ctx.hasLong()) {
                return new Signal(SignalAction.CLOSE_LONG,
                        "跌破 " + fmt(lo), 0.7, StrategyKind.BREAKOUT, ctx.price());
            }
            if (!ctx.hasShort()) {
                return new Signal(SignalAction.SELL,
                        "跌破 " + lb + " 周期低点 " + fmt(lo), 0.7, StrategyKind.BREAKOUT, ctx.price());
            }
        }
        return Signal.hold("在 " + fmt(lo) + " ~ " + fmt(hi) + " 区间内", StrategyKind.BREAKOUT, ctx.price());
    }

    // ------------------------------------------------------------------ 止盈止损（所有策略共用）

    /**
     * 风控检查（按均价计算收益率）。未触发返回 null。
     * 对照 Swift: static func riskCheck(_ ctx: ..., avgPrice:isLong:uplRatioPct:) -> Signal?
     * 注意：与 iOS 一致，uplRatioPct 参数保留但当前未参与计算。
     */
    public static Signal riskCheck(StrategyContext ctx, double avgPrice, boolean isLong, double uplRatioPct) {
        if (avgPrice <= 0) {
            return null;
        }
        Params p = ctx.params();
        double ratio = isLong
                ? (ctx.price() - avgPrice) / avgPrice * 100
                : (avgPrice - ctx.price()) / avgPrice * 100;

        if (ratio <= -p.stopLossPct()) {
            return new Signal(isLong ? SignalAction.CLOSE_LONG : SignalAction.CLOSE_SHORT,
                    "触发止损：浮亏 " + fmt2(ratio) + "% ≤ -" + p.stopLossPct() + "%",
                    1.0, StrategyKind.MA_CROSS, ctx.price());
        }
        if (ratio >= p.takeProfitPct()) {
            return new Signal(isLong ? SignalAction.CLOSE_LONG : SignalAction.CLOSE_SHORT,
                    "触发止盈：浮盈 " + fmt2(ratio) + "% ≥ " + p.takeProfitPct() + "%",
                    1.0, StrategyKind.MA_CROSS, ctx.price());
        }
        return null;
    }

    // ------------------------------------------------------------------ 给 AI 的行情摘要

    /**
     * 组装给 AI 的行情/指标摘要文本。
     * 对照 Swift: static func describe(_ ctx: StrategyContext) -> String
     */
    public static String describe(StrategyContext ctx) {
        Params p = ctx.params();
        List<Double> closes = ctx.closes();
        List<Double> r = Indicator.rsi(closes, p.rsiPeriod());
        List<Double> fast = Indicator.sma(closes, p.fastMA());
        List<Double> slow = Indicator.sma(closes, p.slowMA());

        List<Double> recent = closes.subList(Math.max(0, closes.size() - 10), closes.size());
        StringBuilder recentSb = new StringBuilder();
        for (int i = 0; i < recent.size(); i++) {
            if (i > 0) {
                recentSb.append(", ");
            }
            recentSb.append(fmt2(recent.get(i)));
        }

        List<Candle> last20 = ctx.candles().subList(Math.max(0, ctx.candles().size() - 20), ctx.candles().size());
        double hi = last20.stream().mapToDouble(Candle::high).max().orElse(0);
        double lo = last20.stream().mapToDouble(Candle::low).min().orElse(0);

        String rsiStr = r.isEmpty() ? "N/A" : fmt1(r.get(r.size() - 1));
        String fastStr = fast.isEmpty() ? "N/A" : fmt(fast.get(fast.size() - 1));
        String slowStr = slow.isEmpty() ? "N/A" : fmt(slow.get(slow.size() - 1));

        return "交易对: " + ctx.instId() + "\n"
                + "当前价: " + fmt(ctx.price()) + "\n"
                + "24h 涨跌: " + fmt2(ctx.ticker().changePct()) + "%\n"
                + "24h 最高/最低: " + fmt(ctx.ticker().highDouble()) + " / " + fmt(ctx.ticker().lowDouble()) + "\n"
                + "近 10 根收盘价: " + recentSb + "\n"
                + "近 20 根高点/低点: " + fmt(hi) + " / " + fmt(lo) + "\n"
                + "RSI(" + p.rsiPeriod() + "): " + rsiStr + "\n"
                + "MA" + p.fastMA() + ": " + fastStr + "\n"
                + "MA" + p.slowMA() + ": " + slowStr + "\n"
                + "当前持仓: " + (ctx.hasLong() ? "多头" : ctx.hasShort() ? "空头" : "空仓") + "\n"
                + "止损设置: " + p.stopLossPct() + "%  止盈设置: " + p.takeProfitPct() + "%";
    }

    /**
     * 价格格式化（与 Swift 的 fmt 一致：>=1000 保留 1 位，>=1 保留 3 位，否则 6 位）。
     * 固定 Locale.US，避免某些环境下用逗号做小数点。
     */
    public static String fmt(double v) {
        if (v >= 1000) {
            return String.format(Locale.US, "%.1f", v);
        }
        if (v >= 1) {
            return String.format(Locale.US, "%.3f", v);
        }
        return String.format(Locale.US, "%.6f", v);
    }

    private static String fmt2(double v) {
        return String.format(Locale.US, "%.2f", v);
    }

    private static String fmt1(double v) {
        return String.format(Locale.US, "%.1f", v);
    }
}
