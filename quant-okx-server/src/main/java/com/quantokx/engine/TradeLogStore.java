package com.quantokx.engine;

import com.quantokx.model.TimeFormat;
import com.quantokx.model.TradeLogEntry;
import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.UUID;

/**
 * 交易日志（内存环形存储，最新在前）。
 * 与 iOS 端 TradingEngine.logs 行为一致：最多保留 300 条，新条目插到最前面。
 */
@Component
public class TradeLogStore {

    /** 上限（与 iOS 的 300 条一致） */
    private static final int MAX_ENTRIES = 300;
    /** 契约 GET /api/logs 的默认条数 */
    private static final int DEFAULT_LIMIT = 200;

    private final Deque<TradeLogEntry> logs = new ArrayDeque<>();

    /**
     * 追加一条日志。note 组装规则与 iOS 一致：title +（note 非空时 " · " + note）。
     */
    public synchronized void log(String instId, String title, String action,
                                 double price, double size, String note, boolean ok) {
        String fullNote = (note == null || note.isEmpty()) ? title : title + " · " + note;
        TradeLogEntry entry = new TradeLogEntry(
                UUID.randomUUID().toString(),
                TimeFormat.isoNow(),
                instId,
                action,
                price,
                size,
                fullNote,
                ok);
        logs.addFirst(entry);
        while (logs.size() > MAX_ENTRIES) {
            logs.removeLast();
        }
    }

    /** 最新在前；limit &lt;= 0 时用默认 200，最大 300 */
    public synchronized List<TradeLogEntry> list(int limit) {
        int n = limit <= 0 ? DEFAULT_LIMIT : Math.min(limit, MAX_ENTRIES);
        List<TradeLogEntry> out = new ArrayList<>();
        for (TradeLogEntry e : logs) {
            if (out.size() >= n) {
                break;
            }
            out.add(e);
        }
        return out;
    }

    /** 清空，返回清除条数 */
    public synchronized int clear() {
        int n = logs.size();
        logs.clear();
        return n;
    }

    public synchronized int size() {
        return logs.size();
    }
}
