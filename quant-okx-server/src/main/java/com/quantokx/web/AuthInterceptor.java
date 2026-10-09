package com.quantokx.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.config.QuantOkxProperties;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import java.io.IOException;

/**
 * 鉴权拦截器：除 /api/health 外，所有接口都必须携带 X-Auth-Token 请求头。
 * token 来自 application.yml 的 quantokx.auth-token（默认 changeme，
 * 可用环境变量 QUANT_OKX_AUTH_TOKEN 覆盖）。
 * <p>
 * 401 响应同样使用统一信封：{"code":401,"msg":"未授权：...","data":null}
 */
@Component
public class AuthInterceptor implements HandlerInterceptor {

    private static final String HEADER = "X-Auth-Token";
    private static final String UNAUTHORIZED_MSG = "未授权：X-Auth-Token 缺失或无效";

    private final QuantOkxProperties properties;
    private final ObjectMapper mapper;

    public AuthInterceptor(QuantOkxProperties properties, ObjectMapper mapper) {
        this.properties = properties;
        this.mapper = mapper;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
            throws IOException {
        // CORS 预检请求不带自定义头，直接放行
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return true;
        }
        String expected = properties.getAuthToken();
        String provided = request.getHeader(HEADER);
        if (expected != null && !expected.isEmpty() && expected.equals(provided)) {
            return true;
        }
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write(mapper.writeValueAsString(ApiResponse.error(401, UNAUTHORIZED_MSG)));
        return false;
    }
}
