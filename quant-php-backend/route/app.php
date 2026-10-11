<?php
use think\facade\Route;
use app\middleware\AdminAuth;
use app\middleware\Auth;
use app\middleware\Csrf;

/*
|--------------------------------------------------------------------------
| 路由规则（iOS App 版：网页前端已全部移除，只保留 JSON API）
|--------------------------------------------------------------------------
| route_complete_match 已开启，父路径（如 api/positions）不会抢占子路径
| （如 api/positions/local）。新增接口一律显式声明，避免隐式匹配。
|
| 说明：本版本已移除全部网页页面路由（登录/注册/控制台/OKX/策略/AI/
| 风控/台账/会员/管理端页面）。所有功能统一由 iOS App 客户端 + /api 提供。
*/

/* 安装向导（仅首次部署时使用） */
Route::get('install', 'Install/index');
Route::post('install', 'Install/save')->middleware(Csrf::class);

/* API（全部功能入口） */
Route::group('api', function () {
    /* ---------------- iOS 客户端 JSON 接口 ---------------- */
    Route::post('ios/login', 'api.Ios/login');
    Route::post('ios/register', 'api.Ios/register');
    Route::get('ios/ping', 'api.Ios/ping');
    Route::get('ios/me', 'api.Ios/me');
    Route::post('ios/logout', 'api.Ios/logout');

    Route::get('dashboard', 'api.Dashboard/summary');

    /* ---------------- OKX 账号列表 ---------------- */
    Route::get('okx/config', 'api.Okx/configuration');
    Route::get('okx/accounts', 'api.Okx/accounts');
    Route::post('okx/config', 'api.Okx/save')->middleware(Csrf::class);
    Route::post('okx/account/save', 'api.Okx/save')->middleware(Csrf::class);
    Route::post('okx/account/delete', 'api.Okx/deleteAccount')->middleware(Csrf::class);
    Route::post('okx/account/toggle', 'api.Okx/toggleAccount')->middleware(Csrf::class);
    Route::post('okx/account/test', 'api.Okx/test')->middleware(Csrf::class);
    Route::post('okx/test', 'api.Okx/test')->middleware(Csrf::class);
    Route::get('okx/account', 'api.Okx/account');
    Route::get('okx/balances', 'api.Okx/balances');
    Route::post('okx/leverage', 'api.Okx/setLeverage')->middleware(Csrf::class);

    /* OKX 公共行情 */
    Route::get('okx/ticker', 'api.Okx/ticker');
    Route::get('okx/kline', 'api.Okx/kline');
    Route::get('okx/tickers', 'api.Okx/tickers');
    Route::get('okx/instruments', 'api.Okx/instruments');
    Route::get('okx/instruments/suggest', 'api.Okx/instrumentSuggest');
    Route::get('okx/instruments/check', 'api.Okx/instrumentCheck');
    Route::post('okx/instruments/refresh', 'api.Okx/refreshInstruments')->middleware(Csrf::class);

    /* OKX 交易 */
    Route::get('okx/orders', 'api.Okx/orders');
    Route::post('okx/order/create', 'api.Okx/createOrder')->middleware(Csrf::class);
    Route::post('okx/order/cancel', 'api.Okx/cancelOrder')->middleware(Csrf::class);
    Route::get('okx/positions', 'api.Okx/positions');
    Route::post('okx/position/close', 'api.Okx/closePosition')->middleware(Csrf::class);
    Route::post('okx/reconcile', 'api.Okx/reconcile')->middleware(Csrf::class);
    Route::get('okx/explain', 'api.Okx/explain');
    Route::get('okx/position-mode', 'api.Okx/positionMode');
    Route::post('okx/position-mode', 'api.Okx/setPositionMode')->middleware(Csrf::class);

    /* ---------------- 模拟盘 ---------------- */
    Route::get('paper/status', 'api.Paper/status');
    Route::post('paper/place', 'api.Paper/place')->middleware(Csrf::class);
    Route::post('paper/close', 'api.Paper/close')->middleware(Csrf::class);
    Route::get('paper/local-trading', 'api.Paper/localTrading');
    Route::post('paper/local-trading', 'api.Paper/localTrading')->middleware(Csrf::class);
    Route::post('paper/reset', 'api.Paper/reset')->middleware(Csrf::class);

    /* 通用订单 / 持仓（内部固定 OKX 口径） */
    Route::get('orders', 'api.Order/index');
    Route::post('order/create', 'api.Order/create')->middleware(Csrf::class);
    Route::post('order/cancel', 'api.Order/cancel')->middleware(Csrf::class);
    Route::get('positions', 'api.Position/index');
    Route::get('positions/local', 'api.Position/local');
    Route::post('position/close', 'api.Position/close')->middleware(Csrf::class);

    /* 台账 */
    Route::get('trades', 'api.Ledger/trades');
    Route::get('trades/stats', 'api.Ledger/tradeStats');
    Route::get('profit', 'api.Ledger/profit');
    Route::get('logs/trading', 'api.Ledger/tradingLogs');
    Route::get('logs/system', 'api.Ledger/systemLogs');

    /* ---------------- 策略 ---------------- */
    Route::get('strategies', 'api.Strategy/index');
    Route::get('strategy/meta', 'api.Strategy/meta');
    Route::get('strategy/monitor', 'api.Strategy/monitor');
    Route::post('strategy/create', 'api.Strategy/create')->middleware(Csrf::class);
    Route::post('strategy/update', 'api.Strategy/update')->middleware(Csrf::class);
    Route::post('strategy/delete', 'api.Strategy/delete')->middleware(Csrf::class);
    Route::post('strategy/analyze', 'api.Strategy/analyze')->middleware(Csrf::class);
    Route::post('strategy/start', 'api.Strategy/start')->middleware(Csrf::class);
    Route::post('strategy/stop', 'api.Strategy/stop')->middleware(Csrf::class);
    Route::post('strategy/run', 'api.Strategy/run')->middleware(Csrf::class);
    Route::post('strategy/tick', 'api.Strategy/tick')->middleware(Csrf::class);
    Route::get('strategy/cron', 'api.Strategy/cron');
    Route::get('strategy/cron-url', 'api.Strategy/cronUrl');
    Route::post('strategy/backtest', 'api.Strategy/backtest')->middleware(Csrf::class);

    /* ---------------- AI ---------------- */
    Route::get('ai/list', 'api.Ai/list');
    Route::get('ai/get', 'api.Ai/get');
    Route::post('ai/config', 'api.Ai/saveConfig')->middleware(Csrf::class);
    Route::delete('ai/delete', 'api.Ai/delete')->middleware(Csrf::class);
    Route::post('ai/delete', 'api.Ai/delete')->middleware(Csrf::class);
    Route::post('ai/test', 'api.Ai/testConnection')->middleware(Csrf::class);
    Route::get('ai/diagnose', 'api.Ai/diagnose');
    Route::post('ai/enable', 'api.Ai/enable')->middleware(Csrf::class);
    Route::post('ai/disable', 'api.Ai/disable')->middleware(Csrf::class);
    Route::get('ai/auto/status', 'api.Ai/autoStatus');
    Route::post('ai/auto/start', 'api.Ai/start')->middleware(Csrf::class);
    Route::post('ai/auto/stop', 'api.Ai/stop')->middleware(Csrf::class);
    Route::post('ai/auto/run', 'api.Ai/autoRun')->middleware(Csrf::class);
    Route::post('ai/auto/tick', 'api.Ai/autoTick')->middleware(Csrf::class);
    Route::get('ai/cron', 'api.Ai/cron');
    Route::post('ai/start', 'api.Ai/start')->middleware(Csrf::class);
    Route::post('ai/stop', 'api.Ai/stop')->middleware(Csrf::class);
    Route::get('ai/status', 'api.Ai/status');
    Route::get('ai/reviews', 'api.Ai/reviews');

    /* ---------------- 会员中心 ---------------- */
    Route::get('member/plans', 'api.Member/plans');
    Route::get('member/status', 'api.Member/status');
    Route::get('member/orders', 'api.Member/orders');
    Route::post('member/pay', 'api.Member/pay')->middleware(Csrf::class);

    /* ---------------- 支付回调（免登录，签名校验） ---------------- */
    Route::get('pay/notify', 'api.Pay/notify');
    Route::post('pay/notify', 'api.Pay/notify');
    Route::get('pay/return', 'api.Pay/return');

    /* ---------------- 管理后台（仅管理员，iOS App 内提供界面） ---------------- */
    Route::get('admin/stats', 'api.Admin/stats')->middleware(AdminAuth::class);
    Route::get('admin/users', 'api.Admin/users')->middleware(AdminAuth::class);
    Route::post('admin/user/update', 'api.Admin/userUpdate')->middleware([AdminAuth::class, Csrf::class]);
    Route::get('admin/orders', 'api.Admin/orders')->middleware(AdminAuth::class);
    Route::post('admin/order/mark-paid', 'api.Admin/orderMarkPaid')->middleware([AdminAuth::class, Csrf::class]);
    Route::get('admin/plans', 'api.Admin/plans')->middleware(AdminAuth::class);
    Route::post('admin/plans/save', 'api.Admin/plansSave')->middleware([AdminAuth::class, Csrf::class]);
    Route::get('admin/free-ai', 'api.Admin/freeAi')->middleware(AdminAuth::class);
    Route::post('admin/free-ai/save', 'api.Admin/freeAiSave')->middleware([AdminAuth::class, Csrf::class]);
    Route::get('admin/payment', 'api.Admin/payment')->middleware(AdminAuth::class);
    Route::post('admin/payment/save', 'api.Admin/paymentSave')->middleware([AdminAuth::class, Csrf::class]);
    Route::get('admin/settings', 'api.Admin/settings')->middleware(AdminAuth::class);
    Route::post('admin/settings/save', 'api.Admin/settingsSave')->middleware([AdminAuth::class, Csrf::class]);

    /* 系统 */
    Route::post('system/emergency-stop', 'api.System/emergencyStop')->middleware(Csrf::class);
    Route::post('system/live-trading', 'api.System/toggleLiveTrading')->middleware(Csrf::class);
    Route::post('system/refresh', 'api.System/refresh')->middleware(Csrf::class);
    Route::get('system/automation/status', 'api.System/automationStatus');
    Route::get('system/automation/cron', 'api.System/automationCron');
    Route::get('risk/config', 'api.System/riskConfig');
    Route::post('risk/config', 'api.System/saveRiskConfig')->middleware(Csrf::class);
    Route::get('system/features', 'api.System/features');
})->middleware(Auth::class);

/* 兜底：网页前端已移除，非 API 路径统一返回提示 */
Route::miss(function () {
    return json([
        'code' => 'WEB_UI_REMOVED',
        'message' => '网页前端已移除，全部功能已迁移至 iOS App（QuantOKX）。请打开 App 连接本服务器。',
        'data' => [],
    ], 404);
});
