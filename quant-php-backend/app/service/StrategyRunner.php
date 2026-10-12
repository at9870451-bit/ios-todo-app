<?php
namespace app\service;

use app\model\Strategy;
use app\model\StrategyRun;
use app\model\User;
use Throwable;

/**
 * 策略执行引擎：按每个策略自身配置的模式（paper/testnet/live）、杠杆与置信度阈值执行信号。
 * 所有订单统一经 TradingEngine -> RiskManager。
 */
final class StrategyRunner
{    /** 跑一轮所有启用策略（逐条加锁，避免网页轮询 / 计划任务 / 手动同时触发时重复下单） */
    public static function tick(?int $userId = null, bool $force = false): array
    {
        $query = Strategy::where('enabled', 1);
        if ($userId) $query->where('user_id', $userId);
        $results = [];

        foreach ($query->select() as $row) {
            $id = (int) $row->id;
            $lock = ExecutionLock::acquire('strategy_' . $id);
            if (!$lock) {
                /* 同一策略已有执行者（网页轮询 / 计划任务 / 手动同时命中），本轮跳过，不排队、不重复下单 */
                $results[] = ['strategy_id' => $id, 'skipped' => true, 'reason' => '已有执行者在运行（并发保护）'];
                continue;
            }
            try {
                /* 锁内重新读取最新配置，避免排队期间被停用/修改后仍按旧状态下单 */
                $fresh = Strategy::find($id);
                if (!$fresh) {
                    $results[] = ['strategy_id' => $id, 'skipped' => true, 'reason' => '策略已删除'];
                    continue;
                }
                if (!$force && (int) $fresh->enabled !== 1) {
                    $results[] = ['strategy_id' => $id, 'skipped' => true, 'reason' => '策略已停用'];
                    continue;
                }
                $results[] = self::runOnce($fresh, $force);
            } catch (Throwable $e) {
                self::markRun($id, 'ERROR', null, $e->getMessage());
                SafeLogger::error('策略执行失败', ['strategy_id' => $id, 'message' => $e->getMessage()]);
                $results[] = ['strategy_id' => $id, 'error' => $e->getMessage()];
            } finally {
                ExecutionLock::release($lock);
            }
        }
        return $results;
    }

    /** 执行单个策略一轮 */
    public static function runOnce(Strategy $row, bool $force = false): array
    {
        $user = User::find($row->user_id);
        if (!$user) throw new \RuntimeException('策略所属用户不存在');

        /* 运行间隔节流：未到 run_interval 秒则跳过（手动强制除外），避免定时任务重复下单 */
        if (!$force && (int) ($row->run_interval ?? 0) > 0) {
            $last = StrategyRun::where('strategy_id', $row->id)->find();
            if ($last && !empty($last->last_run_at)) {
                $elapsed = time() - (int) strtotime((string) $last->last_run_at);
                if ($elapsed < (int) $row->run_interval) {
                    return [
                        'strategy_id' => (int) $row->id,
                        'name' => (string) $row->name,
                        'skipped' => true,
                        'reason' => '未到运行间隔（' . $elapsed . 's < ' . (int) $row->run_interval . 's）',
                    ];
                }
            }
        }

        $mode = (string) ($row->mode ?: 'paper');
        if ($mode === 'paper' && !PaperTradingService::localEnabled($user)) {
            /* 本地交易关闭时，paper 策略自动降级为 OKX 模拟盘 */
            $mode = 'testnet';
        }
        /* 会员限制：实盘策略为至尊版功能 */
        if ($mode === 'live' && !MembershipService::can($user, 'live_trade')) {
            throw new \RuntimeException('实盘策略为至尊版功能，请升级会员或把策略切换为模拟盘模式');
        }

        /* 多币种清单：symbols 优先（逗号分隔），单值向后兼容 */
        $symbols = OkxService::normalizeSymbolList((string) ($row->symbols ?: $row->symbol), (string) $row->market_type);
        if (!$symbols) $symbols = [(string) ($row->symbol ?: 'BTC-USDT-SWAP')];

        /* 逐个币种分析 + 执行（单个币种失败不影响其他币种） */
        $results = [];
        $errors = [];
        $traded = 0;
        foreach ($symbols as $symbol) {
            try {
                $one = self::runSymbolOnce($user, $row, $symbol, $mode);
                if (!empty($one['executed'])) $traded++;
                $results[] = $one;
            } catch (Throwable $e) {
                $errors[] = $symbol . '：' . $e->getMessage();
                $results[] = ['symbol' => $symbol, 'signal' => null, 'executed' => false, 'error' => $e->getMessage()];
            }
        }

        $summarySignal = count($symbols) > 1
            ? ($traded . '/' . count($symbols) . ' 下单')
            : (string) ($results[0]['signal'] ?? 'HOLD');
        self::markRun((int) $row->id, 'RUNNING', $summarySignal, $errors ? mb_substr(implode('；', $errors), 0, 480) : null);

        return [
            'strategy_id' => (int) $row->id,
            'name' => (string) $row->name,
            'symbols' => $symbols,
            'results' => $results,
            'executed' => $traded > 0,
            'traded' => $traded,
            'mode' => $mode,
            /* 兼容字段：取第一个币种 */
            'symbol' => (string) ($results[0]['symbol'] ?? ($symbols[0] ?? '')),
            'signal' => (string) ($results[0]['signal'] ?? 'HOLD'),
            'confidence' => (float) ($results[0]['confidence'] ?? 0),
            'threshold' => (float) ($results[0]['threshold'] ?? 0),
            'reason' => (string) ($results[0]['reason'] ?? ''),
        ];
    }

    /** 单个币种的一轮：分析 → 置信度门槛 → 下单（由 runOnce 逐币种调用） */
    private static function runSymbolOnce(User $user, Strategy $row, string $symbol, string $mode): array
    {
        $signal = StrategyService::analyze($user, [
            'symbol' => $symbol,
            'market_type' => $row->market_type,
            'interval' => $row->interval,
            'strategy' => $row->class_name,
            'parameters' => $row->parameters ?: [],
        ]);

        $action = strtoupper((string) ($signal['signal'] ?? 'HOLD'));
        $confidence = (float) ($signal['confidence'] ?? 0);
        $threshold = (float) ($row->min_confidence ?? 0.6);
        $directionMode = DirectionMode::normalize((string) ($row->direction_mode ?? DirectionMode::LONG_ONLY), (string) $row->market_type);
        $decision = DirectionMode::resolve($action, $directionMode);
        $order = null;

        if ($decision['action'] === 'skip') {
            return [
                'symbol' => $symbol,
                'signal' => $action,
                'confidence' => $confidence,
                'threshold' => $threshold,
                'direction_mode' => $directionMode,
                'direction_action' => 'skip',
                'direction_note' => $decision['note'],
                'leverage' => (int) ($row->leverage ?? 1),
                'executed' => false,
                'skipped' => true,
                'reason' => $decision['note'],
                'indicators' => $signal['indicators'] ?? [],
            ];
        }

        /* 置信度门槛 + 非 HOLD 才执行 */
        if ($decision['action'] !== 'hold' && $confidence >= $threshold) {
            $leverage = min(
                (int) RiskManager::config($user)->max_leverage,
                max(1, (int) ($row->leverage ?? 1))
            );
            if ((string) $row->market_type === 'spot') $leverage = 1;

            /* 合约下单前同步杠杆 */
            if ((string) $row->market_type === 'swap' && $mode !== 'paper') {
                $account = \app\model\OkxAccount::where('user_id', $user->id)->where('market_type', 'swap')->find();
                if ($account) {
                    try {
                        (new OkxService($account, 'swap'))->setLeverage(
                            $symbol, $leverage, (string) ($row->td_mode ?: 'cross')
                        );
                    } catch (Throwable $e) {
                        SafeLogger::warning('策略设置杠杆失败', ['strategy_id' => $row->id, 'message' => $e->getMessage()]);
                    }
                }
            }

            /* 防重复开仓：同 symbol 同方向已有持仓时跳过（避免定时任务每轮重复加仓） */
            if (($decision['action'] ?? '') === 'open') {
                $posSideChk = strtoupper((string) ($decision['pos_side'] ?? ''));
                $posQuery = Position::where('user_id', $user->id)
                    ->where('symbol', $symbol)
                    ->where('status', 'OPEN');
                if (in_array($posSideChk, ['LONG', 'SHORT'], true)) $posQuery->where('position_side', $posSideChk);
                if ((int) $posQuery->count() > 0) {
                    return [
                        'symbol' => $symbol,
                        'signal' => $decision['side'] ?? '',
                        'executed' => false,
                        'skipped' => true,
                        'reason' => '已有同方向持仓，跳过重复开仓',
                    ];
                }
            }

            /* 止损止盈强制兜底：策略未配置时按方向以市价近似计算（SL 1.5% / TP 3%） */
            $entryPx = (float) ($signal['price'] ?? 0);
            if ($entryPx <= 0) {
                try {
                    $acct0 = \app\model\OkxAccount::where('user_id', $user->id)->where('market_type', (string) $row->market_type)->find();
                    $tk = (new OkxService($acct0, (string) $row->market_type))->ticker($symbol);
                    $entryPx = (float) ($tk['lastPrice'] ?? 0);
                } catch (\Throwable $e) { $entryPx = 0; }
            }
            $slFinal = (string) ($row->stop_loss ?? '');
            $tpFinal = (string) ($row->take_profit ?? '');
            if ($entryPx > 0) {
                $isBuy = strtolower((string) ($decision['side'] ?? 'buy')) === 'buy';
                if ($slFinal === '' || (float) $slFinal <= 0) {
                    $slFinal = (string) round($isBuy ? $entryPx * 0.985 : $entryPx * 1.015, 6);
                }
                if ($tpFinal === '' || (float) $tpFinal <= 0) {
                    $tpFinal = (string) round($isBuy ? $entryPx * 1.03 : $entryPx * 0.97, 6);
                }
            }
            $order = TradingEngine::execute($user, [
                'symbol' => $symbol,
                'market_type' => $row->market_type,
                'mode' => $mode,
                'side' => $decision['side'],
                'position_side' => $decision['pos_side'],
                'reduce_only' => $decision['reduce_only'],
                'order_type' => 'MARKET',
                'quantity' => (string) ($row->parameters['quantity'] ?? '0.001'),
                'price' => (string) ($signal['price'] ?? ''),
                'stop_loss' => $slFinal,
                'take_profit' => $tpFinal,
                'position_percent' => (float) ($row->position_percent ?: 1),
                'leverage' => $leverage,
                'td_mode' => (string) ($row->td_mode ?: 'cross'),
                'take_profit' => (string) ($row->take_profit ?? ''),
                'stop_loss' => (string) ($row->stop_loss ?? ''),
                'source' => 'STRATEGY',
                'strategy_id' => (int) $row->id,
            ]);
        }

        return [
            'symbol' => $symbol,
            'signal' => $action,
            'confidence' => $confidence,
            'threshold' => $threshold,
            'direction_mode' => $directionMode,
            'direction_action' => $decision['action'],
            'direction_note' => $decision['note'],
            'leverage' => (int) ($row->leverage ?? 1),
            'executed' => (bool) $order,
            'order_id' => $order?->id,
            'reason' => $signal['reason'] ?? '',
            'indicators' => $signal['indicators'] ?? [],
        ];
    }

    /** 记录/更新策略运行状态 */
    private static function markRun(int $strategyId, string $status, ?string $signal, ?string $error): void
    {
        try {
            $run = StrategyRun::where('strategy_id', $strategyId)->find();
            if (!$run) {
                $run = new StrategyRun();
                $run->strategy_id = $strategyId;
            }
            $run->status = $status;
            if ($signal !== null) $run->last_signal = $signal;
            $run->last_run_at = date('Y-m-d H:i:s');
            $run->error_message = $error;
            $run->save();
        } catch (Throwable $e) {
            /* 状态记录失败不影响交易主流程 */
        }
    }

    /** 运行监控列表：策略 + 最近一次运行状态 */
    public static function monitor(User $user): array
    {
        $strategies = Strategy::where('user_id', $user->id)->order('id desc')->select()->toArray();
        $runs = StrategyRun::whereIn('strategy_id', array_column($strategies, 'id') ?: [0])->select()->toArray();
        $runMap = [];
        foreach ($runs as $r) $runMap[(int) $r['strategy_id']] = $r;

        return array_map(static function ($s) use ($runMap) {
            $run = $runMap[(int) $s['id']] ?? null;
            return [
                'id' => (int) $s['id'],
                'name' => $s['name'],
                'class_name' => $s['class_name'],
                'symbol' => $s['symbol'],
                'symbols' => (string) ($s['symbols'] ?? ''),
                'market_type' => $s['market_type'],
                'direction_mode' => DirectionMode::normalize((string) ($s['direction_mode'] ?? DirectionMode::LONG_ONLY), (string) $s['market_type']),
                'interval' => $s['interval'],
                'mode' => $s['mode'],
                'enabled' => (bool) $s['enabled'],
                'leverage' => (int) ($s['leverage'] ?? 1),
                'position_percent' => (float) ($s['position_percent'] ?? 0),
                'min_confidence' => (float) ($s['min_confidence'] ?? 0.6),
                'parameters' => $s['parameters'] ?? [],
                'status' => $run['status'] ?? 'NEVER',
                'last_signal' => $run['last_signal'] ?? null,
                'last_run_at' => $run['last_run_at'] ?? null,
                'error_message' => $run['error_message'] ?? null,
            ];
        }, $strategies);
    }
}
