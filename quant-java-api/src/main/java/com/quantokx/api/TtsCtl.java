package com.quantokx.api;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 开源语音库合成（Piper，MIT 协议）。
 * 服务器本地运行 piper CLI + zh_CN-huayan-medium（中文·华严）模型，离线推理、免密钥。
 * GET /api/tts?text=你好 → audio/wav
 */
@RestController
@RequestMapping("/api/tts")
public class TtsCtl {

    private static final String MODEL_DIR = "/opt/piper-tts/voices/";
    /** piper 推理串行执行，避免多请求挤爆 4 核 CPU */
    private static final Object LOCK = new Object();

    @GetMapping
    public ResponseEntity<byte[]> synth(@RequestParam("text") String text,
                                        @RequestParam(value = "voice", defaultValue = "huayan") String voice) throws Exception {
        String t = text == null ? "" : text.trim();
        if (t.isEmpty()) {
            return ResponseEntity.badRequest().contentType(MediaType.APPLICATION_JSON)
                    .body("{\"code\":\"EMPTY_TEXT\",\"message\":\"文本不能为空\"}".getBytes());
        }
        if (t.length() > 500) t = t.substring(0, 500);
        // 语音名白名单，防路径注入
        String model;
        switch (voice) {
            case "huayan": model = MODEL_DIR + "zh_CN-huayan-medium.onnx"; break;
            default: model = MODEL_DIR + "zh_CN-huayan-medium.onnx";
        }
        java.io.File out = java.io.File.createTempFile("tts-", ".wav");
        try {
            synchronized (LOCK) {
                ProcessBuilder pb = new ProcessBuilder("piper", "-m", model, "-f", out.getAbsolutePath());
                pb.redirectErrorStream(false);
                Process p = pb.start();
                try (java.io.OutputStream os = p.getOutputStream()) {
                    os.write((t + "\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
                    os.flush();
                }
                int code = p.waitFor();
                if (code != 0 || !out.exists() || out.length() == 0) {
                    throw new IllegalStateException("piper exit=" + code);
                }
            }
            byte[] wav = java.nio.file.Files.readAllBytes(out.toPath());
            return ResponseEntity.ok()
                    .contentType(MediaType.parseMediaType("audio/wav"))
                    .header("Cache-Control", "no-store")
                    .body(wav);
        } catch (Exception e) {
            return ResponseEntity.status(500).contentType(MediaType.APPLICATION_JSON)
                    .body(("{\"code\":\"TTS_FAILED\",\"message\":\"语音合成失败: " + e.getMessage() + "\"}")
                            .getBytes(java.nio.charset.StandardCharsets.UTF_8));
        } finally {
            try { java.nio.file.Files.deleteIfExists(out.toPath()); } catch (Exception ignore) {}
        }
    }
}
