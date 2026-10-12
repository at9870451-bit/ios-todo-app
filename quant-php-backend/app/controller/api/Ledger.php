<?php
namespace app\controller\api;

use app\controller\BaseController;
use app\model\Trade;
use app\model\TradingLog;
use app\model\SystemLog;
use app\service\OkxAccountService;
use app\service\OkxService;
use app\service\TradingEngine;
use Throwable;

/**
 * 台账 API：交易历史、成交记录、收益曲线、交易/系统日志。全部为 OKX 口径。
 */
class Ledger extends BaseController
{
    /* 交易历史（成交明细，支持筛选） */
    public function trades()
    {
        try {
            $query = Trade::where('user_id', $this->currentUser()->id)->where('exchange_type', 'okx')->order('id desc');
            $symbol = strtoupper(trim((string) $this->request->param('symbol', '')));
            if ($symbol !== '') $query->where('symbol', 'like', '%' . $symbol . '%');
            $side = strtoupper(trim((string) $this->request->param('side', '')));
            if (in_array($side, ['BUY', 'SELL'], true)) $query->where('side', $side);

            $limit = min(max((int) $this->request->param('limit', 100), 1), 500);
            $items = array_map(static fn ($o) => [
                'id' => (int) $o['id'],
                'symbol' => (string) ($o['symbol'] ?? ''),
                'side' => (string) ($o['side'] ?? ''),
                'price' => (string) ($o['price'] ?? '0'),
                'quantity' => (string) ($o['quantity'] ?? '0'),
                'fee' => isset($o['fee']) ? (string) $o['fee'] : null,
                'trade_time' => $o['trade_time'] ?? null,
                'created_at' => $o['created_at'] ?? null,
            ], $query->limit($limit)->select()->toArray());
            return $this->ok($items);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'TRADE_ERROR', 422);
        }
    }

    /* 交易历史聚合（供前端统计卡片） */
    public function tradeStats()
    {
        try {
            $userId = $this->currentUser()->id;
            $base = Trade::where('user_id', $userId)->where('exchange_type', 'okx');
            $total = (clone $base)->count();
            $buyCount = (clone $base)->where('side', 'BUY')->count();
            $sellCount = (clone $base)->where('side', 'SELL')->count();
            [$volume, $fee] = self::sumVolumeFee(clone $base);

            return $this->ok([
                'total' => $total,
                'buy_count' => $buyCount,
                'sell_count' => $sellCount,
                'volume' => round($volume, 4),
                'fee' => round($fee, 8),
                'by_exchange' => ['okx' => $total],
            ]);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'TRADE_STATS_ERROR', 422);
        }
    }

    /* 收益统计：已实现盈亏 + OKX 资产快照 */
    public function profit()
    {
        try {
            $user = $this->currentUser();
            $days = min(max((int) $this->request->param('days', 30), 1), 365);
            $pnl = TradingEngine::realizedPnl($user, $days);

            /* OKX 资产快照（只读取已配置账户，失败不阻断） */
            $assets = ['okx' => []];
            foreach (['spot', 'swap'] as $type) {
                try {
                    $account = OkxAccountService::account($user, $type);
                    if (!$account) {
                        $assets['okx'][$type] = ['configured' => false, 'total_assets' => '0', 'available_balance' => '0'];
                        continue;
                    }
                    $summary = (new OkxService($account, $type))->accountSummary();
                    $assets['okx'][$type] = [
                        'configured' => true,
                        'total_assets' => (string) ($summary['total_assets'] ?? '0'),
                        'available_balance' => (string) ($summary['available_balance'] ?? '0'),
                        'unrealized_pnl' => (string) ($summary['unrealized_pnl'] ?? '0'),
                    ];
                } catch (Throwable $e) {
                    $assets['okx'][$type] = ['configured' => false, 'total_assets' => '0', 'available_balance' => '0', 'error' => $e->getMessage()];
                }
            }

            $q = Trade::where('user_id', $user->id)->where('exchange_type', 'okx');
            [$volume] = self::sumVolumeFee(clone $q);
            $byExchange = ['okx' => [
                'count' => (clone $q)->count(),
                'volume' => round($volume, 4),
            ]];

            return $this->ok([
                'days' => $days,
                'total_pnl' => $pnl['total'],
                'daily' => $pnl['daily'],
                'curve' => $pnl['curve'],
                'assets' => $assets,
                'by_exchange' => $byExchange,
            ]);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'PROFIT_ERROR', 422);
        }
    }

    /* 交易日志 */
    public function tradingLogs()
    {
        try {
            $query = TradingLog::where('user_id', $this->currentUser()->id)->order('id desc');
            $symbol = strtoupper(trim((string) $this->request->param('symbol', '')));
            if ($symbol !== '') $query->where('symbol', 'like', '%' . $symbol . '%');
            $result = trim((string) $this->request->param('result', ''));
            if ($result !== '') $query->where('result', $result);
            $limit = min(max((int) $this->request->param('limit', 200), 1), 500);
            $items = array_map(static fn ($o) => [
                'id' => (int) $o['id'],
                'symbol' => $o['symbol'] ?? null,
                'source' => $o['source'] ?? null,
                'signal' => $o['signal'] ?? null,
                'price' => isset($o['price']) ? (string) $o['price'] : null,
                'result' => $o['result'] ?? null,
                'pnl' => isset($o['pnl']) ? (string) $o['pnl'] : null,
                'created_at' => $o['created_at'] ?? null,
            ], $query->limit($limit)->select()->toArray());
            return $this->ok($items);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'LOG_ERROR', 422);
        }
    }

    /* 系统日志 */
    public function systemLogs()
    {
        try {
            $query = SystemLog::order('id desc');
            $channel = trim((string) $this->request->param('channel', ''));
            if ($channel !== '') $query->where('channel', $channel);
            $level = trim((string) $this->request->param('level', ''));
            if ($level !== '') $query->where('level', $level);
            $limit = min(max((int) $this->request->param('limit', 200), 1), 500);
            $items = array_map(static fn ($o) => [
                'id' => (int) $o['id'],
                'level' => (string) ($o['level'] ?? 'info'),
                'channel' => (string) ($o['channel'] ?? ''),
                'message' => (string) ($o['message'] ?? ''),
                'created_at' => $o['created_at'] ?? null,
            ], $query->limit($limit)->select()->toArray());
            return $this->ok($items);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'LOG_ERROR', 422);
        }
    }

    /**
     * 汇总成交额（Σ price × quantity）与手续费。
     * 注意：`price * quantity` 是 SQL 表达式，ThinkPHP 的 sum() 只接受字段名，
     * 直接传会抛 "not support data:price * quantity"（收益统计页因此报错）。
     * 这里改为取出两列在 PHP 侧相乘，MySQL / SQLite 均可用。
     */
    private static function sumVolumeFee($query): array
    {
        $volume = 0.0;
        $fee = 0.0;
        foreach ($query->field('price,quantity,fee')->select() as $row) {
            $volume += (float) $row->price * (float) $row->quantity;
            $fee += (float) $row->fee;
        }
        return [$volume, $fee];
    }
}
