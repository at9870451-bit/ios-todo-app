package com.quantokx.indicator;

import java.util.ArrayList;
import java.util.List;

/**
 * 技术指标。逐行对照 iOS 端 Indicator（quant-okx-ios/QuantOKX/Sources/Models/Models.swift），
 * 保证两端数值完全一致。
 */
public final class Indicator {

    private Indicator() {
    }

    /**
     * 简单移动平均。返回序列长度为 max(0, values.size - period + 1)，第 i 个元素对应
     * 原序列下标 (period - 1 + i)。
     * 对照 Swift: static func sma(_ values: [Double], _ period: Int) -> [Double]
     */
    public static List<Double> sma(List<Double> values, int period) {
        if (values.size() < period || period <= 0) {
            return new ArrayList<>();
        }
        List<Double> out = new ArrayList<>();
        double sum = 0.0;
        for (int i = 0; i < values.size(); i++) {
            sum += values.get(i);
            if (i >= period) {
                sum -= values.get(i - period);
            }
            if (i >= period - 1) {
                out.add(sum / period);
            }
        }
        return out;
    }

    /**
     * RSI（Wilder 平滑）。第一个值用前 period 个涨跌幅的简单平均做种子，之后逐根 Wilder 平滑。
     * avgLoss == 0 时输出 100（与 Swift 一致）。
     * 对照 Swift: static func rsi(_ closes: [Double], _ period: Int = 14) -> [Double]
     */
    public static List<Double> rsi(List<Double> closes, int period) {
        if (period <= 0 || closes.size() <= period) {
            return new ArrayList<>();
        }
        List<Double> gains = new ArrayList<>();
        List<Double> losses = new ArrayList<>();
        for (int i = 1; i < closes.size(); i++) {
            double d = closes.get(i) - closes.get(i - 1);
            gains.add(Math.max(d, 0));
            losses.add(Math.max(-d, 0));
        }
        double avgGain = 0.0;
        double avgLoss = 0.0;
        for (int i = 0; i < period; i++) {
            avgGain += gains.get(i);
            avgLoss += losses.get(i);
        }
        avgGain = avgGain / period;
        avgLoss = avgLoss / period;

        List<Double> out = new ArrayList<>();
        out.add(avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss));
        for (int i = period; i < gains.size(); i++) {
            avgGain = (avgGain * (period - 1) + gains.get(i)) / period;
            avgLoss = (avgLoss * (period - 1) + losses.get(i)) / period;
            out.add(avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss));
        }
        return out;
    }

    /**
     * 总体标准差（除以 n，与 Swift 一致；分母是 n 不是 n-1）。
     * 对照 Swift: static func std(_ values: [Double]) -> Double
     */
    public static double std(List<Double> values) {
        if (values.size() <= 1) {
            return 0;
        }
        double mean = 0.0;
        for (double v : values) {
            mean += v;
        }
        mean = mean / values.size();
        double acc = 0.0;
        for (double v : values) {
            double d = v - mean;
            acc += d * d;
        }
        return Math.sqrt(acc / values.size());
    }
}
