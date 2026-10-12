<?php
declare(strict_types=1);
namespace app\service;

use app\model\AiConfig;
use app\model\AiSignal;
use app\model\User;
use RuntimeException;
use Throwable;

/**
 * AI 自动交易引擎。
 *
 * 设计原则：
 *   1. AI 只输出结构化信号，执行永远经过 TradingEngine -> RiskManager，AI 不直接触碰交易所。
 *   2. 每一次自动执行前的硬性门槛（缺一不可）：
 *      - 配置 running = 1 且 enabled = 1
 *      - 未触发全局紧急停止
 *      - trade_mode = demo 时要求绑定 OKX 模拟盘账户；= live 时必须已开启实盘二次开关
 *      - 信号非 HOLD 且 confidence >= min_confidence
 *      - 杠杆不超过该用户风控的 max_leverage
 *   3. 状态全程落库（qb_ai_configs 的 last_run_at / last_signal / run_count / trade_count / error_message），
 *      便于「功能清单」与「AI 自动交易」页面实时展示。
 */
final class AiAutoTraderService
{
    /* ---------------- 运行控制 ---------------- */

    public static function start(User $user, int $configId = 0): array
    {
        $config = self::resolveConfig($user, $configId);
        $risk = RiskManager::config($user);
        if ((int) $risk->emergency_stop === 1) {
            throw new RuntimeException('全局紧急停止已开启，无法启动 AI 自动交易');
        }
        if (!empty($config->provider_config['ai_runtime']['paused'])
            && !AiRiskGuard::policy($config)['circuit_breaker_enabled']) {
            AiRiskGuard::resetRuntime($config);
        }
        if ((string) $config->mode !== 'auto') {
            throw new RuntimeException('仅「自动交易( auto )」模式的 AI 配置可启动；当前为 ' . $config->mode);
        }
        /* 会员限制：自动交易为黄金版及以上功能 */
        MembershipService::assertCan($user, 'auto_trade', 'AI 自动交易为黄金版及以上功能');
        if (self::tradeMode($config) === 'live') {
            MembershipService::assertCan($user, 'live_trade', '实盘自动交易为至尊版功能');
        }
        if (self::tradeMode($config) === 'live' && (int) $user->live_trading_enabled !== 1) {
            throw new RuntimeException('该配置为实盘自动交易，请先在「当前订单」页面开启实盘二次开关');
        }
        if ((int) $config->leverage > (int) $risk->max_leverage) {
            throw new RuntimeException('配置杠杆 ' . $config->leverage . ' 超过风控上限 ' . $risk->max_leverage . '，请下调后再启动');
        }

        $config->running = 1;
        $config->enabled = 1;
        $config->error_message = null;
        AiRiskGuard::resetRuntime($config);
        $config->save();

        SafeLogger::warning('启动 AI 自动交易', [
            'user_id' => $user->id, 'config_id' => $config->id,
            'trade_mode' => self::tradeMode($config), 'symbol' => $config->auto_symbol,
        ]);

        /* 启动后立即执行一轮分析+交易，无需等待轮询间隔 */
        try {
            self::runOnceSafe($config, true);
        } catch (\Throwable $ignore) {
            /* 首轮失败不影响启动状态，后续轮询会继续重试 */
        }
        return self::state($user);
    }

    public static function stop(User $user, int $configId = 0): array
    {
        if ($configId > 0) {
            $config = AiConfig::where('user_id', $user->id)->where('id', $configId)->find();
            if (!$config) throw new RuntimeException('AI 配置不存在');
            $config->running = 0;
            $config->save();
        } else {
            AiConfig::where('user_id', $user->id)->update(['running' => 0]);
        }
        SafeLogger::info('停止 AI 自动交易', ['user_id' => $user->id, 'config_id' => $configId]);
        return self::state($user);
    }

    /** 批量停止所有自动交易（紧急停止联动） */
    public static function stopAll(?int $userId = null): int
    {
        $query = AiConfig::where('running', 1);
        if ($userId) $query->where('user_id', $userId);
        return $query->update(['running' => 0]);
    }

    /* ---------------- 状态 ---------------- */

    public static function state(User $user): array
    {
        $configs = AiConfig::where('user_id', $user->id)->where('mode', 'auto')->order('id desc')->select()->toArray();
        $risk = RiskManager::config($user);
        $running = array_values(array_filter($configs, static fn ($c) => (int) ($c['running'] ?? 0) === 1));

        return [
            'running' => count($running) > 0,
            'running_count' => count($running),
            'auto_config_count' => count($configs),
            'emergency_stop' => (bool) $risk->emergency_stop,
            'live_trading_enabled' => (bool) $user->live_trading_enabled,
            'local_trading_enabled' => PaperTradingService::localEnabled($user),
            'max_leverage' => (int) $risk->max_leverage,
            'cron_url' => '/api/ai/cron?key=' . self::cronKey($user),
            'configs' => array_map(static fn ($c) => [
                'id' => (int) $c['id'],
                'name' => $c['name'],
                'provider_type' => $c['provider_type'],
                'model' => $c['model'],
                'mode' => $c['mode'],
                'enabled' => (bool) $c['enabled'],
                'running' => (bool) ($c['running'] ?? 0),
                'trade_mode' => $c['trade_mode'] ?? 'demo',
                'leverage' => (int) ($c['leverage'] ?? 1),
                'symbol' => $c['auto_symbol'] ?? '',
                'symbols' => self::parseSymbols((string) (($c['auto_symbols'] ?? '') ?: ($c['auto_symbol'] ?? '')), (string) ($c['auto_market_type'] ?? 'swap')),
                'market_type' => $c['auto_market_type'] ?? 'swap',
                'direction_mode' => DirectionMode::normalize((string) ($c['direction_mode'] ?? 'long_only'), (string) ($c['auto_market_type'] ?? 'swap')),
                'ai_risk' => AiRiskGuard::normalizePolicy(is_array($c['provider_config']['ai_risk'] ?? null) ? $c['provider_config']['ai_risk'] : []),
                'ai_runtime' => AiRiskGuard::runtime($c),
                'interval' => $c['auto_interval'] ?? '15m',
                'period_seconds' => (int) ($c['auto_period_seconds'] ?? 300),
                'quantity' => (string) ($c['auto_quantity'] ?? '0'),
                'position_percent' => (float) ($c['auto_position_percent'] ?? 2),
                'capital_usdt' => (float) ($c['capital_usdt'] ?? 0),
                'min_confidence' => (float) ($c['min_confidence'] ?? 0.6),
                'run_count' => (int) ($c['run_count'] ?? 0),
                'trade_count' => (int) ($c['trade_count'] ?? 0),
                'last_run_at' => $c['last_run_at'] ?? null,
                'last_signal' => $c['last_signal'] ?? null,
                'error_message' => $c['error_message'] ?? null,
            ], $configs),
            'risk_guard' => array_map(function ($c) use ($user) {
                $status = AiRiskGuard::status($user, $c);
                return ['config_id' => (int) ($c['id'] ?? 0)] + $status;
            }, $configs),
            'recent_signals' => array_map(static fn ($o) => [
                'id' => (int) $o['id'],
                'symbol' => (string) ($o['symbol'] ?? ''),
                'signal' => (string) ($o['signal'] ?? ''),
                'confidence' => isset($o['confidence']) ? (string) $o['confidence'] : null,
                'entry' => isset($o['entry']) ? (string) $o['entry'] : null,
                'stop_loss' => isset($o['stop_loss']) ? (string) $o['stop_loss'] : null,
                'take_profit' => isset($o['take_profit']) ? (string) $o['take_profit'] : null,
                'reason' => $o['reason'] ?? null,
                'executed' => isset($o['executed']) ? (int) $o['executed'] : null,
                'created_at' => $o['created_at'] ?? null,
            ], AiSignal::where('user_id', $user->id)->order('id desc')->limit(20)->select()->toArray()),
            'recent_reviews' => AiTradeReviewService::recent($user, 20),
        ];
    }

    /* ---------------- 单次执行 ---------------- */

    /**
     * 跑一轮 AI 自动交易（可由 CLI worker 或后台手动触发）。
     * @return array 每个配置的执行结果
     */
    public static function tick(?int $userId = null, bool $force = false): array
    {
        $query = AiConfig::where('mode', 'auto')->where('enabled', 1)->where('running', 1);
        if ($userId) $query->where('user_id', $userId);
        $results = [];

        foreach ($query->select() as $config) {
            $id = (int) $config->id;
            $lock = ExecutionLock::acquire('ai_' . $id);
            if (!$lock) {
                /* 同一 AI 配置已有执行者（网页轮询 / 计划任务 / 手动），本轮跳过，避免重复下单 */
                $results[] = ['config_id' => $id, 'skipped' => true, 'reason' => '已有执行者在运行（并发保护）'];
                continue;
            }
            try {
                /* 锁内复查最新配置：排队期间被停用/停止的不再执行 */
                $fresh = AiConfig::find($id);
                if (!$fresh) {
                    $results[] = ['config_id' => $id, 'skipped' => true, 'reason' => '配置已删除'];
                    continue;
                }
                if (!$force && ((int) $fresh->running !== 1 || (int) $fresh->enabled !== 1)) {
                    $results[] = ['config_id' => $id, 'skipped' => true, 'reason' => '配置未运行（running=0）'];
                    continue;
                }
                $results[] = self::runOnce($fresh, $force);
            } catch (Throwable $e) {
                try {
                    $config->error_message = $e->getMessage();
                    $config->last_run_at = date('Y-m-d H:i:s');
                    $config->run_count = (int) $config->run_count + 1;
                    AiRiskGuard::recordFailure($config, $e->getMessage());
                    $config->save();
                } catch (Throwable $ignore) {
                    /* 状态记录失败不影响其他配置 */
                }
                SafeLogger::error('AI 自动交易执行失败', ['config_id' => $id, 'message' => $e->getMessage()]);
                $results[] = ['config_id' => $id, 'error' => $e->getMessage()];
            } finally {
                ExecutionLock::release($lock);
            }
        }

        return $results;
    }

    /** 执行单个 AI 配置的一轮决策 */
    public static function runOnce(AiConfig $config, bool $force = false): array
    {
        $user = User::find($config->user_id);
        if (!$user) throw new RuntimeException('用户不存在');

        $runtime = AiRiskGuard::runtime($config);
        $riskPolicy = AiRiskGuard::policy($config);
        if (!$force && $runtime['paused'] && $riskPolicy['circuit_breaker_enabled']) {
            return ['config_id' => $config->id, 'stopped' => true, 'paused' => true, 'reason' => $runtime['paused_reason'] ?: 'AI 自动交易处于熔断状态，请重新启动'];
        }

        /* 轮询节流：非强制模式下，未到间隔不执行 */
        if (!$force && $config->last_run_at) {
            $elapsed = time() - strtotime((string) $config->last_run_at);
            if ($elapsed < (int) $config->auto_period_seconds) {
                return ['config_id' => $config->id, 'skipped' => true, 'reason' => '未到轮询间隔（' . $elapsed . 's < ' . $config->auto_period_seconds . 's）'];
            }
        }

        $risk = RiskManager::config($user);
        if ((int) $risk->emergency_stop === 1) {
            $config->running = 0;
            $config->error_message = '全局紧急停止已触发，自动交易已停止';
            $config->save();
            return ['config_id' => $config->id, 'stopped' => true, 'reason' => '紧急停止'];
        }

        /* 会员限制：到期 / 降级后自动停止自动交易（防止过期仍继续执行） */
        if (!MembershipService::can($user, 'auto_trade')) {
            $config->running = 0;
            $config->error_message = '当前会员等级不支持自动交易，已自动停止；请升级会员后重新启动';
            $config->save();
            return ['config_id' => $config->id, 'stopped' => true, 'reason' => '会员等级不足'];
        }

        $marketType = (string) ($config->auto_market_type ?: 'swap');
        $interval = (string) ($config->auto_interval ?: '15m');
        /* 多币种：auto_symbols 优先（逗号分隔），单值向后兼容 */
        $symbols = self::parseSymbols((string) ($config->auto_symbols ?: $config->auto_symbol), $marketType);
        if (!$symbols) $symbols = [$marketType === 'swap' ? 'BTC-USDT-SWAP' : 'BTC-USDT'];
        $tradeMode = self::tradeMode($config);
        $leverage = min((int) $risk->max_leverage, max(1, (int) $config->leverage));

        /* 实盘门槛 */
        if ($tradeMode === 'live' && (int) $user->live_trading_enabled !== 1) {
            throw new RuntimeException('实盘自动交易需要先开启实盘二次开关');
        }
        /* 模拟盘门槛 */
        $account = \app\model\OkxAccount::where('user_id', $user->id)->where('market_type', $marketType)->find();
        if ($tradeMode === 'demo') {
            if (!$account) throw new RuntimeException('未配置 ' . strtoupper($marketType) . ' 市场的 OKX 账户，无法执行模拟盘自动交易：请先在「OKX 账号」页添加 ' . strtoupper($marketType) . ' 的模拟盘（Demo）账户，或在「AI 配置」里把自动交易市场改成已有账户的市场');
            if (!(bool) $account->testnet) throw new RuntimeException('该账户为实盘环境，demo 自动交易需要模拟盘 API 凭据');
        } elseif ($tradeMode === 'local' && !PaperTradingService::localEnabled($user)) {
            throw new RuntimeException('本地交易已关闭，无法执行 local 自动交易');
        }

        /* 逐个币种分析 + 执行（单个币种失败不影响其他币种） */
        $results = [];
        $errors = [];
        $traded = 0;
        foreach ($symbols as $symbol) {
            try {
                $one = self::runSymbolOnce($user, $config, $symbol, $marketType, $interval, $tradeMode, $leverage, $account, $force);
                if (!empty($one['executed'])) $traded++;
                $results[] = $one;
            } catch (Throwable $e) {
                $errors[] = $symbol . '：' . $e->getMessage();
                $results[] = ['symbol' => $symbol, 'signal' => null, 'executed' => false, 'error' => $e->getMessage()];
            }
        }

        $config->last_signal = count($symbols) > 1
            ? ($traded . '/' . count($symbols) . ' 下单')
            : (string) ($results[0]['signal'] ?? 'HOLD');
        $config->last_run_at = date('Y-m-d H:i:s');
        $config->run_count = (int) $config->run_count + 1;
        $config->trade_count = (int) $config->trade_count + $traded;
        $config->error_message = $errors ? mb_substr(implode('；', $errors), 0, 480) : null;
        if ($errors) {
            AiRiskGuard::recordFailure($config, (string) $config->error_message);
        } else {
            AiRiskGuard::clearFailure($config);
        }
        $config->save();

        return [
            'config_id' => (int) $config->id,
            'symbols' => $symbols,
            'results' => $results,
            'executed' => $traded > 0,
            'traded' => $traded,
            'market_type' => $marketType,
            'trade_mode' => $tradeMode,
            'leverage' => $leverage,
            /* 兼容字段：取第一个币种 */
            'symbol' => (string) ($results[0]['symbol'] ?? ($symbols[0] ?? '')),
            'signal' => (string) ($results[0]['signal'] ?? 'HOLD'),
            'confidence' => (float) ($results[0]['confidence'] ?? 0),
            'reason' => (string) ($results[0]['reason'] ?? ''),
        ];
    }

    /** 单个币种的一轮：分析 → 置信度门槛 → 下单（由 runOnce 逐币种调用） */
    private static function runSymbolOnce(User $user, AiConfig $config, string $symbol, string $marketType, string $interval, string $tradeMode, int $leverage, ?\app\model\OkxAccount $account, bool $force = false): array
    {
        $pre = AiRiskGuard::beforeAnalysis($user, $config, $symbol, $force, true);
        if (!$pre['allow']) {
            return [
                'symbol' => $symbol,
                'market_type' => $marketType,
                'signal' => null,
                'confidence' => 0,
                'executed' => false,
                'skipped' => true,
                'risk_blocked' => true,
                'reason' => $pre['reason'],
                'metrics' => $pre['metrics'] ?? [],
            ];
        }

        $result = AiService::analyze($user, [
            'ai_config_id' => (int) $config->id,
            'symbol' => $symbol,
            'market_type' => $marketType,
            'interval' => $interval,
            'mode' => 'analysis',        /* 先只分析，由下面的门槛决定是否执行 */
            'description' => (string) ($config->provider_config['strategy_note'] ?? '按趋势与波动自动判断，严格控制单笔风险。'),
        ]);

        $signal = $result['signal'] ?? [];
        $action = strtoupper((string) ($signal['signal'] ?? 'HOLD'));
        $confidence = (float) ($signal['confidence'] ?? 0);
        $threshold = (float) $config->min_confidence;
        $directionMode = DirectionMode::normalize((string) ($config->direction_mode ?? DirectionMode::LONG_ONLY), $marketType);
        $riskGuard = AiRiskGuard::evaluate($user, $config, $symbol, $signal, (int) ($result['ai_signal_id'] ?? 0), $directionMode, $force);
        $decision = $riskGuard['decision'] ?? DirectionMode::resolve($action, $directionMode);
        $executed = false;
        $order = null;

        if (!$riskGuard['allow']) {
            $blockedReason = $riskGuard['reason'] ?: ($decision['note'] ?? 'AI 风控拦截');
            if (!empty($result['ai_signal_id'])) {
                try {
                    AiSignal::where('id', $result['ai_signal_id'])->update([
                        'reason' => mb_substr($blockedReason, 0, 1000),
                        'response_json' => array_merge($signal, ['risk_guard_reason' => $blockedReason]),
                    ]);
                } catch (Throwable $ignore) { /* 审计写入失败不影响风控拦截 */ }
            }
            return [
                'symbol' => $symbol,
                'market_type' => $marketType,
                'signal' => $action,
                'confidence' => $confidence,
                'threshold' => $threshold,
                'direction_mode' => $directionMode,
                'direction_action' => $decision['action'] ?? 'skip',
                'direction_note' => $decision['note'] ?? '',
                'executed' => false,
                'skipped' => true,
                'risk_blocked' => true,
                'reason' => $blockedReason,
                'metrics' => $riskGuard['metrics'] ?? [],
            ];
        }

        if ($decision['action'] !== 'hold' && $decision['action'] !== 'skip' && ($decision['action'] === 'close' || $confidence >= $threshold)) {
            /* 合约先同步杠杆 */
            if ($marketType === 'swap' && $tradeMode !== 'local' && $account) {
                try {
                    (new OkxService($account, 'swap'))->setLeverage($symbol, $leverage, (string) ($config->provider_config['td_mode'] ?? 'cross'));
                } catch (Throwable $e) {
                    SafeLogger::warning('AI 自动交易设置杠杆失败', ['symbol' => $symbol, 'message' => $e->getMessage()]);
                }
            }

            $engineMode = $tradeMode === 'local' ? 'paper' : 'testnet';
            if ($tradeMode === 'live') $engineMode = 'live';

            $order = TradingEngine::execute($user, [
                'symbol' => $symbol,
                'market_type' => $marketType,
                'mode' => $engineMode,
                'side' => $decision['side'],
                'position_side' => $decision['pos_side'],
                'reduce_only' => $decision['reduce_only'],
                'order_type' => 'MARKET',
                'quantity' => (string) ($config->auto_quantity ?: '0.001'),
                'price' => (string) ($signal['entry'] ?? ''),
                'stop_loss' => (string) ($signal['stop_loss'] ?? ''),
                'take_profit' => (string) ($signal['take_profit'] ?? ''),
                'position_percent' => (float) ($config->auto_position_percent ?: 1),
                'leverage' => $leverage,
                'source' => 'AI',
                'ai_signal_id' => (int) ($result['ai_signal_id'] ?? 0),
            ]);
            $executed = true;

            if (!empty($result['ai_signal_id'])) {
                AiSignal::where('id', $result['ai_signal_id'])->update(['executed' => 1]);
            }
        }

        return [
            'symbol' => $symbol,
            'market_type' => $marketType,
            'signal' => $action,
            'confidence' => $confidence,
            'threshold' => $threshold,
            'direction_mode' => $directionMode,
            'direction_action' => $decision['action'],
            'direction_note' => $decision['note'],
            'executed' => $executed,
            'order_id' => $order?->id,
            'reason' => $signal['reason'] ?? '',
        ];
    }

    /** 解析多币种清单（委托 OkxService 统一实现：去重、最多 12 个、按市场补后缀） */
    public static function parseSymbols(string $raw, string $marketType): array
    {
        return OkxService::normalizeSymbolList($raw, $marketType);
    }

    /** 获取/生成该用户的「计划任务 key」（与策略定时任务共用），供 /api/ai/cron 使用 */
    public static function cronKey(User $user): string
    {
        return PlanKeyService::forUser($user);
    }

    /** 跑一轮（安全版）：失败时记录到配置并返回错误结果，不向上抛异常 */
    public static function runOnceSafe(AiConfig $config, bool $force = false): array
    {
        try {
            return self::runOnce($config, $force);
        } catch (Throwable $e) {
            $config->error_message = $e->getMessage();
            $config->last_run_at = date('Y-m-d H:i:s');
            $config->run_count = (int) $config->run_count + 1;
            AiRiskGuard::recordFailure($config, $e->getMessage());
            $config->save();
            SafeLogger::error('AI 自动交易执行失败', ['config_id' => $config->id, 'message' => $e->getMessage()]);
            return ['config_id' => (int) $config->id, 'error' => $e->getMessage()];
        }
    }

    /* ---------------- 内部 ---------------- */

    private static function resolveConfig(User $user, int $configId): AiConfig
    {
        if ($configId > 0) {
            $config = AiConfig::where('user_id', $user->id)->where('id', $configId)->find();
            if (!$config) throw new RuntimeException('AI 配置不存在');
            return $config;
        }
        $config = AiConfig::where('user_id', $user->id)->where('mode', 'auto')->order('id desc')->find();
        if (!$config) throw new RuntimeException('没有 auto 模式的 AI 配置，请先在「AI 配置」中创建并选择自动交易模式');
        return $config;
    }

    /** demo=OKX 官方模拟盘 / live=实盘 / local=本地撮合 */
    public static function tradeMode(AiConfig $config): string
    {
        $mode = (string) ($config->trade_mode ?: 'demo');
        return in_array($mode, ['demo', 'live', 'local'], true) ? $mode : 'demo';
    }
}
