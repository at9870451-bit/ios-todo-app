<?php
namespace app\service;

use app\model\OkxAccount;
use app\model\Order;
use app\model\Position;
use app\model\TradingLog;
use app\model\User;
use RuntimeException;

/**
 * 统一接收手动、策略和 AI 订单意图。
 * 只对接 OKX（spot / swap），三种模式：paper（本地撮合）、testnet（OKX 模拟盘）、live（实盘）。
 * 策略与 AI 本身不接触交易所，全部经此引擎执行。
 */
final class TradingEngine
{
    public static function execute(User $user, array $input): Order
    {
        $input = self::normalize($input);
        RiskManager::check($user, $input);

        $clientId = $input['client_order_id'] ?: self::clientId();
        $existing = Order::where('user_id', $user->id)->where('client_order_id', $clientId)->find();
        if ($existing) return $existing;

        $marketType = $input['market_type'];
        $mode = $input['mode'];

        /* ---- 取得本地价格（用于模拟盘成交价与限价校验） ---- */
        $price = (string) ($input['price'] ?: '0');
        if ((float) $price <= 0) {
            $price = self::marketPrice($marketType, $input['symbol']);
        }
        if ((float) $price <= 0) throw new RuntimeException('无法取得有效价格，请手动填写价格');

        /* ---- 交易所账户与下单 ---- */
        $order = new Order();
        $order->user_id = $user->id;
        $order->exchange_type = 'okx';
        $order->client_order_id = $clientId;
        $order->symbol = $input['symbol'];
        $order->market_type = $marketType;
        $order->mode = $mode;
        $order->side = $input['side'];
        $order->position_side = $input['position_side'] ?: null;
        $order->order_type = $input['order_type'];
        $order->price = $price;
        $order->quantity = $input['quantity'];
        $order->executed_quantity = '0';
        $order->stop_loss = $input['stop_loss'] ?: null;
        $order->take_profit = $input['take_profit'] ?: null;
        $order->status = 'PENDING_SUBMIT';
        $order->source = $input['source'];
        $order->strategy_id = $input['strategy_id'] ?: null;
        $order->ai_signal_id = $input['ai_signal_id'] ?: null;

        if ($mode !== 'paper') {
            $account = OkxAccountService::account($user, $marketType);
            if (!$account) throw new RuntimeException('请先配置对应 OKX API 账户');
            if ($mode === 'testnet' && !(bool) $account->testnet) throw new RuntimeException('模拟盘模式要求该 OKX 账户启用模拟盘环境');
            if ($mode === 'live' && (bool) $account->testnet) throw new RuntimeException('实盘模式要求该 OKX 账户关闭模拟盘环境');
            $order->account_id = $account->id;
        }

        $order->save();

        /* ---- 模拟盘：本地成交（需显式开启本地交易开关） ---- */
        if ($mode === 'paper') {
            if (!PaperTradingService::localEnabled($user)) {
                throw new RuntimeException('本地交易已关闭：请使用 OKX 官方模拟盘（mode=testnet），或在模拟盘交易台开启本地交易');
            }
            $order->status = 'FILLED';
            $order->executed_quantity = $input['quantity'];
            $order->updated_at = date('Y-m-d H:i:s');
            $order->save();
            /* 先按成交前持仓计算已实现盈亏，再更新本地双向持仓镜像。 */
            $realized = self::recordTrade(
                $user,
                $order,
                $price,
                (string) ($input['position_side'] ?? ''),
                (bool) ($input['reduce_only'] ?? false)
            );
            PositionManager::applyPaper(
                (int) $user->id,
                $order->account_id,
                $marketType,
                'okx',
                $input['symbol'],
                $input['side'],
                $input['quantity'],
                $price,
                $input['leverage'],
                (string) ($input['position_side'] ?? ''),
                (bool) ($input['reduce_only'] ?? false)
            );
            self::log($user, $order, 'PAPER_FILLED', ['price' => $price, 'pnl' => $realized, 'leverage' => $input['leverage'], 'position_side' => $input['position_side']]);
            return $order;
        }

        /* ---- 交易所提交 ---- */
        try {
            $client = new OkxService($account, $marketType);

            /* ⓪ 显式指定了杠杆：下单前同步到交易所（失败不阻断，仅留痕）。
               这样 AI / 策略 / 手动单都会使用用户选择的杠杆。 */
            if ($marketType === 'swap' && !empty($input['leverage_provided'])) {
                try {
                    $client->setLeverage($input['symbol'], (int) $input['leverage'], (string) ($input['td_mode'] ?: 'cross'));
                    self::log($user, $order, 'LEVERAGE_SET', ['leverage' => (int) $input['leverage'], 'td_mode' => $input['td_mode'] ?: 'cross']);
                } catch (\Throwable $e) {
                    SafeLogger::warning('下单前设置杠杆失败', [
                        'symbol' => $input['symbol'], 'leverage' => $input['leverage'], 'message' => $e->getMessage(),
                    ]);
                    self::log($user, $order, 'LEVERAGE_SET_FAILED', ['leverage' => (int) $input['leverage'], 'message' => $e->getMessage()]);
                }
            }

            /* ① 按产品规格规范化数量与价格，避免因精度问题被 OKX 拒绝。
               永续的数量单位是「张」：把用户输入的「币数量」按合约面值 ctVal 自动换算。 */
            $submitQty = (string) $input['quantity'];
            $submitPx = (string) ($input['price'] ?: $price);
            $isLimit = !in_array(strtoupper((string) $input['order_type']), ['MARKET'], true);
            $qtyNote = '';

            $spec = ['instId' => $input['symbol'], 'lotSz' => '', 'minSz' => '', 'tickSz' => '', 'ctVal' => '', 'ctValCcy' => ''];
            try {
                $found = $client->instrument($input['symbol']);
                if ($found) $spec = $found;

                /* 永续：币数量 -> 张（仅当合约面值币种与基础币一致） */
                if ($marketType === 'swap' && $found) {
                    $conv = self::coinsToContractsQty($submitQty, $spec);
                    if ($conv['converted']) {
                        $submitQty = (string) $conv['qty'];
                        $qtyNote = (string) $conv['note'];
                    }
                }

                if (!empty($spec['lotSz'])) {
                    $submitQty = self::alignToStep($submitQty, (string) $spec['lotSz']);
                    if ($isLimit) $submitPx = self::alignToStep($submitPx, (string) $spec['tickSz']);
                    $minSz = (float) ($spec['minSz'] ?? 0);
                    if ($minSz > 0 && (float) $submitQty < $minSz) {
                        throw new RuntimeException(self::minSizeMessage(
                            $input['symbol'], $marketType, (string) $input['quantity'], $submitQty, $spec, $qtyNote !== ''
                        ));
                    }
                }
            } catch (RuntimeException $e) {
                throw $e; /* 规格不符属于业务错误，直接抛给用户 */
            } catch (\Throwable $e) {
                /* 拉不到产品列表时跳过规范化，交由 OKX 自己校验 */
            }

            $order->quantity = $submitQty;
            if ($isLimit) $order->price = $submitPx;

            /* 持仓模式联动：双向持仓必须带 posSide；净持仓不能带 posSide。 */
            if ($marketType === 'swap') {
                try {
                    $positionMode = $client->positionMode();
                    if ($positionMode === 'long_short_mode') {
                        if ((string) ($input['position_side'] ?? '') === '') {
                            $input['position_side'] = strtoupper((string) $input['side']) === 'BUY' ? 'long' : 'short';
                            self::log($user, $order, 'POS_SIDE_AUTO', [
                                'position_side' => $input['position_side'],
                                'symbol' => $input['symbol'],
                            ]);
                        }
                    } else {
                        /* net_mode 下 OKX 会拒绝 posSide=long/short，剥离方向字段。 */
                        $input['position_side'] = '';
                    }
                } catch (\Throwable $e) {
                    /* 读取失败不阻断：交由 OKX 返回明确错误，保留已选方向。 */
                }
            }

            /* 所有开单强制带止盈止损：未提供时按方向自动补默认（SL 1.5% / TP 3%，盈亏比 2:1）。
               仅对永续开仓/加仓单生效；平仓（reduce_only）单不需要。 */
            if ($marketType === 'swap' && empty($input['reduce_only'])) {
                $refPx = (float) ($price ?: 0);
                if ($refPx <= 0 && !empty($input['price'])) $refPx = (float) $input['price'];
                if ($refPx > 0) {
                    $isBuy = strtoupper((string) $input['side']) === 'BUY';
                    if ((string) ($input['stop_loss'] ?? '') === '' || (float) $input['stop_loss'] <= 0) {
                        $input['stop_loss'] = (string) round($isBuy ? $refPx * 0.985 : $refPx * 1.015, 6);
                    }
                    if ((string) ($input['take_profit'] ?? '') === '' || (float) $input['take_profit'] <= 0) {
                        $input['take_profit'] = (string) round($isBuy ? $refPx * 1.03 : $refPx * 0.97, 6);
                    }
                    $order->stop_loss = $input['stop_loss'];
                    $order->take_profit = $input['take_profit'];
                }
            }

            /* 止盈止损：校验方向后随单附带给 OKX（仅永续；方向不符自动跳过，不拖累主单） */
            $tpSl = ['stop_loss' => '', 'take_profit' => '', 'skipped' => []];
            if ($marketType === 'swap') {
                $tpSl = self::sanitizeTpSl(
                    (string) $input['side'],
                    (string) $price,
                    (string) ($input['stop_loss'] ?? ''),
                    (string) ($input['take_profit'] ?? '')
                );
                if ($tpSl['stop_loss'] !== '' || $tpSl['take_profit'] !== '') {
                    self::log($user, $order, 'TP_SL_ATTACHED', [
                        'stop_loss' => $tpSl['stop_loss'],
                        'take_profit' => $tpSl['take_profit'],
                    ]);
                }
                if (!empty($tpSl['skipped'])) {
                    self::log($user, $order, 'TP_SL_SKIPPED', ['reasons' => $tpSl['skipped']]);
                }
            }

            /* ② 提交订单 */
            $response = $client->createOrder([
                'symbol' => $input['symbol'],
                'side' => $input['side'],
                'type' => $input['order_type'],
                'quantity' => $submitQty,
                /* 市价单不携带保护价（px）：避免因保护价限制出现「挂上但没成交」，
                   确保 AI / 手动市价单在无仓位时也能直接开出仓位 */
                'price' => $isLimit ? $submitPx : '',
                'td_mode' => $input['td_mode'],
                'pos_side' => $input['position_side'],
                'reduce_only' => $input['reduce_only'],
                'stop_loss' => $tpSl['stop_loss'],
                'take_profit' => $tpSl['take_profit'],
            ]);

            $order->okx_order_id = (string) ($response['ordId'] ?? '');
            $order->status = (string) ($response['status'] ?? 'NEW');
            if ($qtyNote !== '') {
                $response['_qty_note'] = $qtyNote; /* 记录「币 -> 张」换算，事后可核对 */
                self::log($user, $order, 'QTY_CONVERTED', ['note' => $qtyNote, 'instId' => $input['symbol']]);
            }
            $order->raw_response = $response;
            $order->updated_at = date('Y-m-d H:i:s');
            $order->save();

            /* ③ 立即回查交易所，确认订单真实存在（防止「本地显示成功、交易所没有」） */
            $verified = null;
            try {
                $detail = $client->orderDetail($input['symbol'], $order->okx_order_id, $order->client_order_id);
                if (!empty($detail['ordId'])) {
                    $verified = true;
                    $state = (string) ($detail['state'] ?? '');
                    if ($state !== '') $order->status = $state;
                    /* 空串消毒：accFillSz 为空时保持原值，避免写 decimal 报 1366 */
                    $filled = OkxService::num($detail['accFillSz'] ?? null, '');
                    if ($filled !== '') $order->executed_quantity = $filled;
                    $order->raw_response = $detail;
                    $order->updated_at = date('Y-m-d H:i:s');
                    $order->save();
                } else {
                    $verified = false;
                }
            } catch (\Throwable $e) {
                /* 回查失败不影响下单结果，但记录下来备查 */
                SafeLogger::warning('下单后回查失败', [
                    'ordId' => $order->okx_order_id,
                    'symbol' => $input['symbol'],
                    'message' => $e->getMessage(),
                ]);
            }

            /* 只有确认有成交数量/成交状态时才建立开仓或平仓复盘记录。 */
            $filledState = in_array(strtoupper((string) $order->status), ['FILLED', 'PARTIALLY_FILLED'], true)
                || (float) $order->executed_quantity > 0;
            $realized = 0.0;
            if ($filledState) {
                $realized = self::recordTrade(
                    $user,
                    $order,
                    (string) ($order->executed_quantity > 0 ? $order->price : $submitPx),
                    (string) ($input['position_side'] ?? ''),
                    (bool) ($input['reduce_only'] ?? false)
                );
            }
            self::log($user, $order, 'EXCHANGE_SUBMITTED', [
                'exchange' => 'okx',
                'order_id' => $order->okx_order_id,
                'verified' => $verified,
                'market_type' => $marketType,
                'mode' => $mode,
                'pnl' => $realized,
                'position_side' => $input['position_side'],
            ]);
            return $order;
        } catch (\Throwable $e) {
            /* 区分「明确被拒」与「结果未知」：
               - OkxApiException 且带有 OKX 错误码 => 交易所明确拒绝，标记 REJECTED
               - 网络超时 / 无响应 => 结果未知，标记 UNKNOWN 需人工对账 */
            $isExplicitReject = $e instanceof OkxApiException
                && ($e->diagnostics()['okx_code'] || $e->diagnostics()['sub_code']);

            $reason = $e instanceof OkxApiException
                ? $e->summary()
                : '网络异常，无法确认交易所是否已受理：' . $e->getMessage();

            $order->status = $isExplicitReject ? 'REJECTED' : 'UNKNOWN';
            $order->reject_reason = mb_substr($reason, 0, 480);
            $order->updated_at = date('Y-m-d H:i:s');
            $order->save();

            self::log($user, $order, $isExplicitReject ? 'LIVE_REJECTED' : 'SUBMIT_UNKNOWN', [
                'exchange' => 'okx',
                'reason' => $reason,
                'diagnostics' => $e instanceof OkxApiException ? $e->diagnostics() : null,
            ]);

            /* 把可读原因抛给上层，前端 toast 与订单记录都能看到真实原因 */
            throw new RuntimeException($reason, (int) $e->getCode(), $e);
        }
    }

    public static function cancel(User $user, int $orderId): Order
    {
        $order = Order::where('user_id', $user->id)->where('id', $orderId)->find();
        if (!$order) throw new RuntimeException('订单不存在');
        if ($order->mode === 'paper') {
            $order->status = 'CANCELED';
            $order->save();
            return $order;
        }
        if (!$order->okx_order_id) throw new RuntimeException('订单没有交易所订单号');

        $account = OkxAccount::where('id', $order->account_id)->where('user_id', $user->id)->find();
        if (!$account) throw new RuntimeException('交易账户不存在');
        $response = (new OkxService($account, (string) $order->market_type))
            ->cancelOrder((string) $order->symbol, (string) $order->okx_order_id);
        $order->status = 'CANCELED';
        $order->raw_response = $response;
        $order->save();
        self::log($user, $order, 'CANCELED', ['exchange' => 'okx']);
        return $order;
    }

    /**
     * 获取 OKX 公共最新价（无需凭据）
     */
    private static function marketPrice(string $marketType, string $symbol): string
    {
        try {
            /* normalize() 已把 symbol 规范成 instId 形式，这里直接使用 */
            $ticker = (new OkxService(null, $marketType))->ticker($symbol);
            return (string) ($ticker['lastPrice'] ?? '0');
        } catch (\Throwable $e) {
            return '0';
        }
    }

    private static function normalize(array $input): array
    {
        $input['exchange_type'] = 'okx';
        $input['symbol'] = strtoupper(trim((string) ($input['symbol'] ?? '')));
        $input['market_type'] = (string) ($input['market_type'] ?? 'spot');
        if (!in_array($input['market_type'], ['spot', 'swap'], true)) $input['market_type'] = 'spot';
        $input['mode'] = strtolower((string) ($input['mode'] ?? 'paper'));
        if (!in_array($input['mode'], ['paper', 'testnet', 'live'], true)) $input['mode'] = 'paper';
        $input['side'] = strtoupper((string) ($input['side'] ?? 'BUY'));
        $input['order_type'] = strtoupper((string) ($input['order_type'] ?? 'MARKET'));
        $input['quantity'] = trim((string) ($input['quantity'] ?? '0'));
        $input['price'] = trim((string) ($input['price'] ?? ''));
        $input['stop_loss'] = trim((string) ($input['stop_loss'] ?? ''));
        $input['take_profit'] = trim((string) ($input['take_profit'] ?? ''));
        $input['stop_price'] = trim((string) ($input['stop_price'] ?? ''));
        $input['time_in_force'] = strtoupper((string) ($input['time_in_force'] ?? 'GTC'));
        $input['position_side'] = strtolower(trim((string) ($input['position_side'] ?? '')));
        if (!in_array($input['position_side'], ['long', 'short'], true)) $input['position_side'] = '';
        $input['td_mode'] = strtolower((string) ($input['td_mode'] ?? ''));
        /* 现货为 cash，永续为 cross/isolated；留空时由 OkxService 按市场类型决定 */
        if (!in_array($input['td_mode'], ['cross', 'isolated', 'cash'], true)) $input['td_mode'] = '';
        if ($input['market_type'] === 'spot') $input['td_mode'] = 'cash';
        /* 永续未指定时默认全仓 cross（cash 仅适用于现货） */
        if ($input['market_type'] === 'swap' && !in_array($input['td_mode'], ['cross', 'isolated'], true)) $input['td_mode'] = 'cross';
        $input['reduce_only'] = !empty($input['reduce_only']);
        /* 杠杆：合约 1~125，现货恒为 1；记录用户是否显式指定（显式时才同步到交易所） */
        $levRaw = trim((string) ($input['leverage'] ?? ''));
        $input['leverage_provided'] = ($levRaw !== '');
        $input['leverage'] = min(125, max(1, (int) ($levRaw === '' ? 1 : $levRaw)));
        if ($input['market_type'] === 'spot') $input['leverage'] = 1;
        $input['client_order_id'] = trim((string) ($input['client_order_id'] ?? ''));
        $input['source'] = (string) ($input['source'] ?? 'MANUAL');
        $input['strategy_id'] = (int) ($input['strategy_id'] ?? 0);
        $input['ai_signal_id'] = (int) ($input['ai_signal_id'] ?? 0);

        /* OKX 交易对格式自动规范化（单一事实来源在 OkxService::normalizeInstId）：
           BTCUSDT / BTC-USDT / BTC-USDT-SWAP 均可；永续自动补 -SWAP 后缀，
           否则会被 OKX 当现货单处理（曾导致 sCode=59110） */
        $input['symbol'] = OkxService::normalizeInstId((string) $input['symbol'], (string) $input['market_type']);
        return $input;
    }

    private static function clientId(): string
    {
        return 'qb_' . date('ymdHis') . '_' . bin2hex(random_bytes(5));
    }

    /**
     * 把数值对齐到交易所步长（lotSz / tickSz），并去掉多余小数位。
     * 例：qty=0.0013 lotSz=0.001 => 0.001
     */
    private static function alignToStep(string $value, string $step): string
    {
        $v = (float) $value;
        $s = (float) $step;
        if ($v <= 0 || $s <= 0) return $value;

        $decimals = 0;
        $stepStr = rtrim(rtrim(number_format($s, 12, '.', ''), '0'), '.');
        if (strpos($stepStr, '.') !== false) {
            $decimals = strlen(substr($stepStr, strpos($stepStr, '.') + 1));
        }
        $steps = floor(round($v / $s, 8));
        $aligned = $steps * $s;
        return number_format($aligned, $decimals, '.', '');
    }

    /**
     * 永续合约「币数量 -> 张数」换算（纯函数，便于测试）。
     * 仅当合约面值币种与基础币一致时换算（如 ctValCcy=BTC 对应 BTC-USDT-SWAP）；
     * 逆合约（如 ctValCcy=USD）不换算，交由 OKX 校验并给出提示。
     */
    public static function coinsToContractsQty(string $coinsQty, array $spec): array
    {
        $ctVal = (float) ($spec['ctVal'] ?? 0);
        $ctValCcy = (string) ($spec['ctValCcy'] ?? '');
        $instId = (string) ($spec['instId'] ?? '');
        $base = explode('-', $instId)[0] ?? '';
        $coins = (float) $coinsQty;

        if ($ctVal <= 0 || $base === '' || strcasecmp($ctValCcy, $base) !== 0 || $coins <= 0) {
            return ['converted' => false, 'qty' => $coinsQty, 'note' => ''];
        }
        $contracts = $coins / $ctVal;
        return [
            'converted' => true,
            'qty' => self::trimNum($contracts),
            'note' => $coinsQty . ' ' . $base . ' ≈ ' . self::trimNum($contracts) . ' 张（合约面值 ' . self::trimNum($ctVal) . ' ' . $ctValCcy . '/张）',
        ];
    }

    /**
     * 止盈止损方向校验（纯函数）：只有方向合理才随单提交给交易所，
     * 避免「多头单带高于现价的止盈」这类错误拖累主订单。
     * 多头（BUY）：止损 < 参考价 < 止盈；空头（SELL）：止盈 < 参考价 < 止损。
     */
    public static function sanitizeTpSl(string $side, string $refPrice, string $stopLoss, string $takeProfit): array
    {
        $ref = (float) $refPrice;
        $isBuy = strtoupper($side) === 'BUY';
        $sl = trim($stopLoss);
        $tp = trim($takeProfit);
        $skipped = [];

        if ($sl !== '') {
            $value = (float) $sl;
            if ($value <= 0 || $ref <= 0 || ($isBuy ? $value >= $ref : $value <= $ref)) {
                $skipped[] = '止损价 ' . $sl . ' 与' . ($isBuy ? '多头' : '空头') . '开仓参考价 ' . $refPrice . ' 方向不符，已跳过附带';
                $sl = '';
            }
        }
        if ($tp !== '') {
            $value = (float) $tp;
            if ($value <= 0 || $ref <= 0 || ($isBuy ? $value <= $ref : $value >= $ref)) {
                $skipped[] = '止盈价 ' . $tp . ' 与' . ($isBuy ? '多头' : '空头') . '开仓参考价 ' . $refPrice . ' 方向不符，已跳过附带';
                $tp = '';
            }
        }
        return ['stop_loss' => $sl, 'take_profit' => $tp, 'skipped' => $skipped];
    }

    /** 「低于最小下单量」的中文提示（永续带上张数 / 合约面值解释） */    public static function minSizeMessage(string $symbol, string $marketType, string $inputQty, string $submitQty, array $spec, bool $converted = false): string
    {
        $minSz = (string) ($spec['minSz'] ?? '0');
        $lotSz = (string) ($spec['lotSz'] ?? '0');
        $base = explode('-', $symbol)[0] ?? '';
        $ctVal = (float) ($spec['ctVal'] ?? 0);
        $ccy = (string) ($spec['ctValCcy'] ?? '');

        if ($marketType === 'swap') {
            $msg = $converted
                ? '数量 ' . $inputQty . ' 换算后为 ' . $submitQty . ' 张，低于 ' . $symbol . ' 的最小下单量 ' . $minSz . ' 张（步长 ' . $lotSz . ' 张）'
                : '下单数量 ' . $submitQty . ' 张，低于 ' . $symbol . ' 的最小下单量 ' . $minSz . ' 张（步长 ' . $lotSz . ' 张）';
            if ($ctVal > 0 && $ccy !== '' && strcasecmp($ccy, $base) === 0) {
                $msg .= '；1 张 = ' . self::trimNum($ctVal) . ' ' . $ccy
                    . '，最少约 ' . self::trimNum((float) $minSz * $ctVal) . ' ' . $base
                    . '，请按 ' . $lotSz . ' 的整数倍填写';
            }
            return $msg;
        }
        return '下单数量 ' . $submitQty . ' 小于产品最小下单量 ' . $minSz
            . '（' . $symbol . '，步长 ' . $lotSz . '）';
    }

    /** 去掉数字尾部的 0 与小数点：0.100 → 0.1，1.000 → 1 */
    private static function trimNum(float $value): string
    {
        return rtrim(rtrim(number_format($value, 12, '.', ''), '0'), '.');
    }

    /**
     * 记录成交（qb_trades），并在平仓方向返回已实现盈亏。
     * position_side/reduce_only 由 AI 双向模式传入；旧调用仍可用三个参数。
     */
    private static function recordTrade(User $user, Order $order, string $price, string $positionSide = '', bool $reduceOnly = false): float
    {
        $qty = (float) ($order->executed_quantity ?: $order->quantity);
        $px = (float) $price;
        if ($qty <= 0 || $px <= 0) return 0.0;

        $positionSide = strtolower(trim($positionSide ?: (string) ($order->position_side ?? '')));
        if (!in_array($positionSide, ['long', 'short', 'both'], true)) $positionSide = '';
        $query = Position::where('user_id', $user->id)
            ->where('exchange_type', 'okx')
            ->where('market_type', $order->market_type)
            ->where('symbol', $order->symbol);
        if ($positionSide !== '' && $positionSide !== 'both') $query->where('position_side', strtoupper($positionSide));
        $position = $query->order('id desc')->find();
        if ($position && $positionSide === '') $positionSide = strtolower((string) $position->position_side);
        if (!in_array($positionSide, ['long', 'short', 'both'], true)) $positionSide = 'both';

        $entry = $position ? (float) $position->entry_price : 0.0;
        $leverage = in_array((string) $order->market_type, ['swap', 'futures'], true)
            ? max(1, (int) ($position->leverage ?? 1)) : 1;
        $side = strtoupper((string) $order->side);
        $isClose = $reduceOnly
            || ($positionSide === 'long' && $side === 'SELL')
            || ($positionSide === 'short' && $side === 'BUY')
            || ($positionSide === 'both' && $side === 'SELL' && $position !== null);
        $fee = $order->mode === 'paper' ? $qty * $px * 0.0005 : 0.0;
        $realized = 0.0;
        if ($isClose && $entry > 0) {
            $gross = $positionSide === 'short'
                ? ($entry - $px) * $qty * $leverage
                : ($px - $entry) * $qty * $leverage;
            $realized = $gross - $fee;
        }

        try {
            $trade = new \app\model\Trade();
            $trade->order_id = $order->id;
            $trade->user_id = $user->id;
            $trade->exchange_type = 'okx';
            $trade->okx_trade_id = $order->okx_order_id ?: ('local_' . $order->client_order_id);
            $trade->symbol = $order->symbol;
            $trade->side = $order->side;
            $trade->price = number_format($px, 18, '.', '');
            $trade->quantity = number_format($qty, 18, '.', '');
            $trade->fee = number_format($fee, 18, '.', '');
            $trade->fee_asset = 'USDT';
            $trade->trade_time = date('Y-m-d H:i:s');
            $trade->save();
        } catch (\Throwable $e) {
            /* 交易记录写入失败不影响主流程 */
        }

        try {
            $reviewSide = $positionSide === 'both'
                ? ($side === 'SELL' ? 'long' : 'short')
                : $positionSide;
            AiTradeReviewService::onFilled(
                $user,
                $order,
                $realized,
                $entry,
                $px,
                $reviewSide,
                $isClose,
                $leverage
            );
        } catch (\Throwable $e) {
            /* 复盘是旁路能力，任何异常都不能回滚已成交订单。 */
            SafeLogger::warning('AI 成交复盘旁路失败', ['order_id' => $order->id, 'message' => $e->getMessage()]);
        }
        return $realized;
    }

    /**
     * 计算账户维度已实现盈亏汇总（收益统计使用）
     */
    public static function realizedPnl(User $user, int $days = 30): array
    {
        $since = date('Y-m-d 00:00:00', strtotime('-' . max($days, 1) . ' days'));
        $rows = \app\model\TradingLog::where('user_id', $user->id)
            ->where('pnl', '<>', 0)
            ->where('created_at', '>=', $since)
            ->select()->toArray();

        $byDay = [];
        $total = 0.0;
        foreach ($rows as $row) {
            $pnl = (float) $row['pnl'];
            $total += $pnl;
            $day = substr((string) $row['created_at'], 0, 10);
            $byDay[$day] = ($byDay[$day] ?? 0) + $pnl;
        }
        ksort($byDay);

        $curve = [];
        $cum = 0.0;
        foreach ($byDay as $day => $pnl) {
            $cum += $pnl;
            $curve[] = ['time' => $day, 'value' => round($cum, 4), 'daily' => round($pnl, 4)];
        }

        return ['total' => round($total, 4), 'daily' => $byDay, 'curve' => $curve];
    }

    private static function log(User $user, Order $order, string $result, array $metadata): void
    {
        TradingLog::create([
            'user_id' => $user->id, 'order_id' => $order->id, 'symbol' => $order->symbol,
            'source' => $order->source, 'signal' => $order->side, 'price' => $order->price,
            'quantity' => $order->quantity, 'direction' => $order->side, 'result' => $result,
            'pnl' => (float) ($metadata['pnl'] ?? 0),
            'metadata' => $metadata,
        ]);
    }
}
