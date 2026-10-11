<?php
declare(strict_types=1);
namespace app\middleware;

use app\service\InstallerService;
use Closure;

/** 未安装时将所有请求导向安装向导；已安装时访问安装路径直接提示。（网页前端已移除，本向导仅部署用） */
class InstallGuard
{
    public function handle($request, Closure $next)
    {
        $path = trim((string) $request->pathinfo(), '/');
        $installPath = $path === 'install' || str_starts_with($path, 'install/');
        if (!InstallerService::installed() && !$installPath) return redirect('/install');
        if (InstallerService::installed() && $installPath) {
            /* 网页已移除：已安装后安装向导不再开放，直接回到 App 提示 */
            return json([
                'code' => 'WEB_UI_REMOVED',
                'message' => '系统已安装完成，网页前端已移除，请使用 iOS App 客户端（QuantOKX）',
                'data' => [],
            ], 404);
        }
        return $next($request);
    }
}
