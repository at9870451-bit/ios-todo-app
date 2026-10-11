<?php
namespace app\middleware;

use Closure;
use app\service\ApiResponse;
use think\facade\Session;

/** 登录保护：后台页面与 /api 统一要求已登录。 */
class Auth
{
    public function handle($request, Closure $next)
    {
        $path = trim($request->pathinfo(), '/');
        /* 计划任务入口：用「计划任务 key」自校验，无需登录会话（供服务器 cron / 宝塔计划任务调用） */
        if (in_array($path, ['api/ai/cron', 'api/strategy/cron', 'api/system/automation/cron', 'api/pay/notify', 'api/pay/return'], true)) {
            return $next($request);
        }
        /* iOS 客户端登录前接口：登录/注册/连通性自检免登录（me/logout 仍由控制器内部校验） */
        if (in_array($path, ['api/ios/login', 'api/ios/register', 'api/ios/ping'], true)) {
            return $next($request);
        }
        /* 管理端 API：管理端独立会话（admin_user_id）同样有效，角色校验交给 AdminAuth 中间件 */
        if (Session::get('user_id') || (str_starts_with($path, 'api/admin') && Session::get('admin_user_id'))) {
            return $next($request);
        }
        if (str_starts_with($path, 'api/')) {
            return ApiResponse::error('未登录或会话已过期', 'UNAUTHORIZED', 401);
        }
        return redirect('/login');
    }
}
