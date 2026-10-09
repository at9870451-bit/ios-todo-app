package com.quantokx.engine;

import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Locale;

/**
 * 风控：每小时下单次数（滑动窗口）+ 最大持仓上限 + 单笔金额。
 * 所有下单入口（引擎自动交易、手动下单）都必须先过这里。
 * <p>
 * 与 iOS 端语义一致：
 * - 频率检查对「开仓和平仓」都生效（平仓同样占用配额）；
 * - 只有真正下单成功才调用 recordTrade() 占用配额；
 * - 持仓上限只用「真实名义价值（USDT）」比较，超出即拒绝。
 */
@Component
public class RiskManager {

    private static final long WINDOW_MS = 3600_000L;

    /** 最近一小时内的下单时间戳（毫秒），双端队列保持有序 */
    private final Deque<Long> tradeTimes = new ArrayDeque<>();

    /**
     * 频率限制检查。通过返回 null，否则返回给用户看的中文原因（与 iOS 文案一致）。
     */
    public synchronized String checkFrequency(int maxTradesPerHour) {
        prune(System.currentTimeMillis());
        if (tradeTimes.size() >= maxTradesPerHour) {
            return "触发频率限制（1 小时最多 " + maxTradesPerHour + " 笔）";
        }
        return null;
    }

    /**
     * 开仓前检查：单笔金额 + 最大持仓上限。
     *
     * @param singleUsdt           本单名义价值（USDT）
     * @param currentNotionalUsdt  当前已有持仓名义价值（USDT，同一 instId）
     * @param maxPositionUsdt      配置的最大持仓上限（USDT）
     * @return 通过返回 null，否则返回中文原因
     */
    public synchronized String checkOpenOrder(double singleUsdt, double currentNotionalUsdt, double maxPositionUsdt) {
        if (!(singleUsdt > 0)) {
            return "单笔金额必须大于 0";
        }
        if (currentNotionalUsdt + singleUsdt > maxPositionUsdt) {
            return "超出最大持仓上限 " + formatUsdt(maxPositionUsdt) + " USDT";
        }
        return null;
    }

    /** 下单成功后调用（占用频率配额） */
    public synchronized void recordTrade() {
        long now = System.currentTimeMillis();
        prune(now);
        tradeTimes.addLast(now);
    }

    /** 最近一小时内的下单次数（供调试/展示） */
    public synchronized int tradesInLastHour() {
        prune(System.currentTimeMillis());
        return tradeTimes.size();
    }

    private void prune(long now) {
        while (!tradeTimes.isEmpty() && now - tradeTimes.peekFirst() >= WINDOW_MS) {
            tradeTimes.removeFirst();
        }
    }

    /** 与 iOS 的 Int(config.maxPositionUSDT) 展示效果保持一致（取整） */
    private static String formatUsdt(double v) {
        return String.format(Locale.US, "%.0f", v);
    }
}
