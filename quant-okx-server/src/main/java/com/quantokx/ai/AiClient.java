package com.quantokx.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.quantokx.model.SignalAction;
import com.quantokx.okx.OkxException;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Locale;

/**
 * 兼容 OpenAI Chat Completions 格式的 AI 客户端。
 * 改 baseURL 就能换成任何兼容服务（DeepSeek / 通义 / 本地 Ollama / 自建代理…）。
 * <p>
 * 对照 quant-okx-ios/QuantOKX/Sources/Networking/AIClient.swift：
 * - 宽松解析模型输出（去掉 ```json 包裹、取第一个 { 到最后一个 }）；
 * - confidence < 0.6 且不是 hold 时，一律降级为 hold。
 */
@Component
public class AiClient {

    private static final String SYSTEM_PROMPT = """
            你是一个专业的加密货币量化交易决策引擎。你会收到实时行情和技术指标，需要输出一个交易决策。

            决策原则：
            1. 宁可错过，不可做错。信号不明确时选择 hold。
            2. 趋势行情跟随均线；震荡行情参考 RSI 与区间位置。
            3. 已有持仓时优先考虑止盈止损，不要频繁反手。
            4. confidence 反映你的把握程度，0.6 以下请直接给 hold。

            只输出一个 JSON 对象，不要任何解释文字、不要 markdown 代码块：
            {"action":"buy|sell|hold|closeLong|closeShort","confidence":0.0-1.0,"reason":"20字以内的中文理由"}
            """;

    private final HttpClient http;
    private final ObjectMapper mapper;

    public AiClient(ObjectMapper mapper) {
        this.mapper = mapper;
        this.http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
    }

    /** AI 决策结果 */
    public record Decision(SignalAction action, double confidence, String reason) {
    }

    /**
     * 调用 AI 接口做一次决策。对照 Swift: func decide(context: String) async throws -> Decision
     *
     * @param baseURL chat completions 完整地址
     * @param model   模型名
     * @param apiKey  密钥（为空则不发送 Authorization 头）
     * @param context 行情摘要（StrategyEngine.describe 的输出）
     */
    public Decision decide(String baseURL, String model, String apiKey, String context) throws OkxException {
        URI uri;
        try {
            uri = URI.create(baseURL);
        } catch (IllegalArgumentException e) {
            throw new OkxException("bad-url", "AI 接口地址无效");
        }

        ObjectNode payload = mapper.createObjectNode();
        payload.put("model", model == null ? "" : model);
        payload.put("temperature", 0.2);
        payload.put("max_tokens", 200);
        ArrayNode messages = payload.putArray("messages");
        messages.addObject().put("role", "system").put("content", SYSTEM_PROMPT);
        messages.addObject().put("role", "user").put("content", context);

        String body;
        try {
            body = mapper.writeValueAsString(payload);
        } catch (IOException e) {
            throw new OkxException("encode", "AI 请求体序列化失败");
        }

        HttpRequest.Builder builder = HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(45))
                .header("Content-Type", "application/json");
        if (apiKey != null && !apiKey.isEmpty()) {
            builder.header("Authorization", "Bearer " + apiKey);
        }
        HttpRequest request = builder
                .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8))
                .build();

        HttpResponse<String> resp;
        try {
            resp = http.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new OkxException("network", "网络错误：" + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new OkxException("network", "AI 请求被中断");
        }
        if (resp.statusCode() < 200 || resp.statusCode() >= 300) {
            throw new OkxException("http-" + resp.statusCode(), "AI 接口返回异常（HTTP " + resp.statusCode() + "）");
        }

        JsonNode root;
        try {
            root = mapper.readTree(resp.body());
        } catch (IOException e) {
            throw new OkxException("decode", "AI 返回不是合法 JSON");
        }
        JsonNode content = root.path("choices").path(0).path("message").path("content");
        if (!content.isTextual()) {
            throw new OkxException("decode", "AI 未返回内容");
        }
        return parse(content.asText());
    }

    /**
     * 宽松解析模型输出。对照 Swift: func parse(_ text: String) -> Decision
     * 模型有时会包 ```json 或加解释，这里做宽松提取。
     */
    public Decision parse(String text) {
        String s = text == null ? "" : text;
        int fence = s.indexOf("```json");
        if (fence >= 0) {
            s = s.substring(fence + 7);
        }
        int fence2 = s.indexOf("```");
        if (fence2 >= 0) {
            s = s.substring(0, fence2);
        }

        int start = s.indexOf('{');
        int end = s.lastIndexOf('}');
        if (start < 0 || end < 0 || start >= end) {
            return new Decision(SignalAction.HOLD, 0, "AI 回复无法解析，保持观望");
        }
        String jsonStr = s.substring(start, end + 1);

        JsonNode obj;
        try {
            obj = mapper.readTree(jsonStr);
        } catch (IOException e) {
            return new Decision(SignalAction.HOLD, 0, "AI 回复 JSON 非法");
        }
        if (obj == null || !obj.isObject()) {
            return new Decision(SignalAction.HOLD, 0, "AI 回复 JSON 非法");
        }

        String actionRaw = obj.path("action").asText("hold");
        SignalAction action = SignalAction.fromWireOrNull(actionRaw);
        if (action == null) {
            action = SignalAction.HOLD;
        }

        double conf = 0;
        JsonNode confNode = obj.get("confidence");
        if (confNode != null && !confNode.isNull()) {
            if (confNode.isNumber()) {
                conf = confNode.asDouble();
            } else if (confNode.isTextual()) {
                try {
                    conf = Double.parseDouble(confNode.asText());
                } catch (NumberFormatException e) {
                    conf = 0;
                }
            }
        }

        String reason = obj.path("reason").isTextual() ? obj.get("reason").asText() : "AI 未说明理由";

        // 低置信度一律降级为观望（与 iOS 一致）
        if (conf < 0.6 && action != SignalAction.HOLD) {
            return new Decision(SignalAction.HOLD, conf,
                    "AI 置信度偏低（" + String.format(Locale.US, "%.2f", conf) + "），观望");
        }
        return new Decision(action, conf, reason);
    }
}
