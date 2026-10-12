<?php
declare(strict_types=1);
namespace app\service;

use app\model\AiConfig;
use app\model\AiSignal;
use app\model\AiTradeReview;
use app\model\Order;
use app\model\User;
use Throwable;

/** AI 成交结果留痕与自动复盘。复盘失败只标记失败，不影响订单主链路。 */
final class AiTradeReviewService
{
    /**
     * 成交成功后调用：开仓先建立 OPEN 记录，平仓计算已实现盈亏并自动请求 AI 复盘。
     */
    public static function onFilled(
        User $user,
        Order $order,
        float $realizedPnl,
        float $entryPrice,
        float $exitPrice,
        string $positionSide,
        bool $isClose,
        int $leverage = 1
    ): void {
        if (strtoupper((string) $order->source) !== 'AI') return;

        $positionSide = in_array(strtolower($positionSide), ['long', 'short'], true)
            ? strtolower($positionSide)
            : (strtoupper((string) $order->side) === 'BUY' ? 'long' : 'short');
        $signal = self::signal($order);
        $configId = $signal ? (int) ($signal->ai_config_id ?? 0) : 0;
        $qty = (float) ($order->executed_quantity ?: $order->quantity);
        $leverage = max(1, $leverage);

        if (!$isClose) {
            /* 同方向允许加仓时，每次开仓各自保留一条待复盘记录。 */
            $review = new AiTradeReview();
            $review->user_id = $user->id;
            $review->ai_config_id = $configId ?: null;
            $review->ai_signal_id = $order->ai_signal_id ?: null;
            $review->entry_order_id = $order->id;
            $review->order_id = null;
            $review->symbol = (string) $order->symbol;
            $review->market_type = (string) $order->market_type;
            $review->position_side = $positionSide;
            $review->entry_price = $entryPrice;
            $review->exit_price = null;
            $review->quantity = $qty;
            $review->leverage = $leverage;
            $review->pnl = 0;
            $review->pnl_percent = 0;
            $review->status = 'OPEN';
            $review->review_text = '持仓中，平仓后自动复盘';
            $review->save();
            return;
        }

        /* 优先把对应的开仓记录闭合；没有本地开仓记录时仍建立完整的平仓复盘记录。 */
        $review = AiTradeReview::where('user_id', $user->id)
            ->where('symbol', (string) $order->symbol)
            ->where('position_side', $positionSide)
            ->where('status', 'OPEN')
            ->order('id desc')->find();
        if (!$review) $review = new AiTradeReview();

        $review->user_id = $user->id;
        $review->ai_config_id = $review->ai_config_id ?: ($configId ?: null);
        $review->ai_signal_id = $review->ai_signal_id ?: ($order->ai_signal_id ?: null);
        $review->entry_order_id = $review->entry_order_id ?: null;
        $review->order_id = $order->id;
        $review->symbol = (string) $order->symbol;
        $review->market_type = (string) $order->market_type;
        $review->position_side = $positionSide;
        $review->entry_price = $entryPrice > 0 ? $entryPrice : ($review->entry_price ?: null);
        $review->exit_price = $exitPrice;
        $review->quantity = $qty;
        $review->leverage = $leverage;
        $review->pnl = round($realizedPnl, 8);
        $notional = max(0.00000001, abs((float) $review->entry_price * $qty));
        $review->pnl_percent = round(($realizedPnl / $notional) * 100, 8);
        $review->status = 'PENDING';
        $review->review_text = '已成交，正在自动复盘';
        $review->reviewed_at = null;
        $review->save();

        self::run($user, $review, $order, $signal);
    }

    public static function recent(User $user, int $limit = 20): array
    {
        try {
            /* 显式字段映射：原始行 id 为字符串、数值列为字符串，App 端需要整数/字符串明确类型 */
            $items = array_map(static fn ($o) => [
                'id' => (int) $o['id'],
                'symbol' => (string) ($o['symbol'] ?? ''),
                'market_type' => (string) ($o['market_type'] ?? 'swap'),
                'position_side' => $o['position_side'] ?? null,
                'entry_price' => isset($o['entry_price']) ? (string) $o['entry_price'] : null,
                'exit_price' => isset($o['exit_price']) ? (string) $o['exit_price'] : null,
                'quantity' => isset($o['quantity']) ? (string) $o['quantity'] : null,
                'leverage' => (int) ($o['leverage'] ?? 1),
                'pnl' => isset($o['pnl']) ? (string) $o['pnl'] : null,
                'pnl_percent' => isset($o['pnl_percent']) ? (string) $o['pnl_percent'] : null,
                'status' => (string) ($o['status'] ?? 'OPEN'),
                'review_text' => $o['review_text'] ?? null,
                'error_message' => $o['error_message'] ?? null,
                'reviewed_at' => $o['reviewed_at'] ?? null,
                'created_at' => $o['created_at'] ?? null,
            ], AiTradeReview::where('user_id', $user->id)->order('id desc')->limit(max(1, min(100, $limit)))->select()->toArray());
            return $items;
        } catch (Throwable $e) {
            return [];
        }
    }

    private static function run(User $user, AiTradeReview $review, Order $order, ?AiSignal $signal): void
    {
        try {
            $context = [
                'symbol' => (string) $review->symbol,
                'market_type' => (string) $review->market_type,
                'position_side' => (string) $review->position_side,
                'entry_price' => (float) $review->entry_price,
                'exit_price' => (float) $review->exit_price,
                'quantity' => (float) $review->quantity,
                'leverage' => (int) $review->leverage,
                'pnl' => (float) $review->pnl,
                'pnl_percent' => (float) $review->pnl_percent,
                'outcome' => (float) $review->pnl < 0 ? 'loss' : ((float) $review->pnl > 0 ? 'profit' : 'flat'),
                'signal' => $signal ? [
                    'signal' => $signal->signal,
                    'confidence' => (float) $signal->confidence,
                    'stop_loss' => (float) $signal->stop_loss,
                    'take_profit' => (float) $signal->take_profit,
                    'reason' => (string) $signal->reason,
                ] : [],
            ];
            $configId = $review->ai_config_id ? (int) $review->ai_config_id : 0;
            $result = AiService::reviewTrade($user, $context, $configId);
            $review->review_json = $result;
            $review->review_text = self::text($result);
            $review->status = 'SUCCESS';
            $review->error_message = null;
            $review->reviewed_at = date('Y-m-d H:i:s');
            $review->save();
        } catch (Throwable $e) {
            $review->status = 'FAILED';
            $review->error_message = mb_substr($e->getMessage(), 0, 500);
            $review->review_text = '自动复盘失败：' . $review->error_message;
            $review->reviewed_at = date('Y-m-d H:i:s');
            try { $review->save(); } catch (Throwable $ignore) {}
            SafeLogger::warning('AI 交易自动复盘失败', [
                'user_id' => $user->id,
                'order_id' => $order->id,
                'message' => $e->getMessage(),
            ]);
        }
    }

    private static function signal(Order $order): ?AiSignal
    {
        $id = (int) ($order->ai_signal_id ?? 0);
        return $id > 0 ? AiSignal::find($id) : null;
    }

    private static function text(array $result): string
    {
        foreach (['review', 'summary', 'conclusion', 'message'] as $key) {
            if (isset($result[$key]) && is_scalar($result[$key]) && trim((string) $result[$key]) !== '') {
                return mb_substr((string) $result[$key], 0, 2000);
            }
        }
        return mb_substr((string) json_encode($result, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), 0, 2000);
    }
}
