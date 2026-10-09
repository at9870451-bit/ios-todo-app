package com.quantokx.model;

import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;

/**
 * 时间格式化工具。契约要求 ISO-8601 秒级 UTC 字符串，如 2026-10-10T04:30:00Z
 * （不带毫秒，保证 iOS 端 ISO8601DateFormatter 默认格式可解析）。
 */
public final class TimeFormat {

    private TimeFormat() {
    }

    public static String iso(Instant instant) {
        if (instant == null) {
            return null;
        }
        return DateTimeFormatter.ISO_INSTANT.format(instant.truncatedTo(ChronoUnit.SECONDS));
    }

    public static String isoNow() {
        return iso(Instant.now());
    }
}
