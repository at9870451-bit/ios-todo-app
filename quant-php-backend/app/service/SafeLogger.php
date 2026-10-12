<?php
declare(strict_types=1);
namespace app\service;

use Throwable;
use think\facade\Log;

/** 只写入不含敏感凭据的业务日志，日志不可用时不得阻断主流程。 */
final class SafeLogger
{
    public static function info(string $message, array $context = []): void { self::write('info', $message, $context); }
    public static function warning(string $message, array $context = []): void { self::write('warning', $message, $context); }
    public static function error(string $message, array $context = []): void { self::write('error', $message, $context); }

    private static function write(string $level, string $message, array $context): void
    {
        $line = $message . (self::encode($context) ? ' ' . self::encode($context) : '');
        try {
            if ($level === 'error') Log::error($line);
            elseif ($level === 'warning') Log::warning($line);
            else Log::info($line);
        } catch (Throwable $e) { error_log('[QuantOKX] ' . $line); }
        self::mirror($level, $message, $context);
    }

    /* 同步重要事件到 qb_system_logs（App「系统日志」页数据源）。
       info 级别仅白名单事件入库，避免高频心跳刷表；写入失败静默。 */
    private static function mirror(string $level, string $message, array $context): void
    {
        try {
            if ($level === 'info') {
                $important = ['登录', '注册', '下单', '平仓', '订单', '会员', '支付', '启动', '停止', '紧急', '实盘', '升级', '开通', '策略'];
                $hit = false;
                foreach ($important as $kw) {
                    if (mb_strpos($message, $kw) !== false) { $hit = true; break; }
                }
                if (!$hit) return;
            }
            $log = new \app\model\SystemLog();
            $log->user_id = isset($context['user_id']) ? (int) $context['user_id'] : null;
            $log->level = $level;
            $log->channel = self::channel($message);
            $log->message = mb_substr($message . (self::encode($context) ? ' ' . self::encode($context) : ''), 0, 1000);
            $log->ip = isset($context['ip']) ? (string) $context['ip'] : null;
            $log->save();
        } catch (\Throwable $e) { /* 静默：日志镜像失败不影响业务 */ }
    }

    private static function channel(string $m): string
    {
        if (mb_strpos($m, '登录') !== false || mb_strpos($m, '注册') !== false) return 'auth';
        if (mb_strpos($m, '下单') !== false || mb_strpos($m, '订单') !== false || mb_strpos($m, '平仓') !== false) return 'trade';
        if (mb_strpos($m, 'AI') !== false) return 'ai';
        if (mb_strpos($m, '策略') !== false) return 'strategy';
        if (mb_strpos($m, '会员') !== false || mb_strpos($m, '支付') !== false) return 'member';
        return 'system';
    }

    private static function encode(array $context): string
    {
        $blocked = ['api_key', 'api_secret', 'secret', 'password', 'token', 'authorization'];
        foreach ($blocked as $key) unset($context[$key]);
        return $context ? (string) json_encode($context, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : '';
    }
}
