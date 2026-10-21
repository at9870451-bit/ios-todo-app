package com.quantokx.dollstudio.db;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.util.FileCopyUtils;

import java.nio.charset.StandardCharsets;

/** 启动时执行 schema.sql（CREATE TABLE IF NOT EXISTS，幂等），并注入种子数据 */
@Component
public class SchemaInit implements CommandLineRunner {

    @Autowired
    private JdbcTemplate jdbc;

    @Override
    public void run(String... args) throws Exception {
        String sql = new String(FileCopyUtils.copyToByteArray(
                new ClassPathResource("schema.sql").getInputStream()), StandardCharsets.UTF_8);
        // 按分号拆分执行（schema.sql 不含存储过程；INSERT IGNORE 幂等）
        for (String stmt : sql.split(";")) {
            String t = stmt.replaceAll("--[^\\n]*", "").trim();
            if (t.isEmpty()) continue;
            jdbc.execute(t);
        }
        ensureAdmin();
    }

    private void ensureAdmin() {
        Integer n = jdbc.queryForObject("SELECT COUNT(*) FROM admins WHERE username = 'admin'", Integer.class);
        if (n != null && n == 0) {
            String hash = new BCryptPasswordEncoder().encode("Admin@2026");
            jdbc.update("INSERT INTO admins (username, password_hash, role) VALUES ('admin', ?, 'admin')", hash);
            System.out.println("[DollStudio] 已创建管理员 admin / Admin@2026 —— 请立即修改密码！");
        }
    }
}
