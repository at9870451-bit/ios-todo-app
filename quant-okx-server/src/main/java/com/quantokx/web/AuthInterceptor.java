package com.quantokx.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.auth.SessionStore;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import java.io.IOException;

/**
 * 会话鉴权：除 /api/health、/api/pay/notify、/api/pay/return 外，
 * 所有接口都必须携带 X-Auth-Token（登录/注册签发的会话令牌）。
 * 校验通过后把 userId 放进 request attribute，控制器据此定位该用户的引擎与配置。
 */
@Component
public class AuthInterceptor implements HandlerInterceptor {

    /** 请求属性名：当前登录用户 id */
    public static final String ATTR_USER_ID = "userId";

    private static final String HEADER = "X-Auth-Token";
    private static final String UNAUTHORIZED_MSG = "未授权：请先登录（X-Auth-Token 缺失或已过期）";

    private final SessionStore sessions;
    private final ObjectMapper mapper;

    public AuthInterceptor(SessionStore sessions, ObjectMapper mapper) {
        this.sessions = sessions;
        this.mapper = mapper;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
            throws IOException {
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return true;
        }
        String userId = sessions.resolve(request.getHeader(HEADER));
        if (userId != null) {
            request.setAttribute(ATTR_USER_ID, userId);
            return true;
        }
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write(mapper.writeValueAsString(ApiResponse.error(401, UNAUTHORIZED_MSG)));
        return false;
    }
}