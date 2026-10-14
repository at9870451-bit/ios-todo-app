<template>
  <div>
    <el-result icon="warning" title="404" sub-title="页面不存在或已被移除">
      <template #extra>
        <el-button type="primary" @click="$router.push('/')">返回控制台</el-button>
      </template>
    </el-result>
  </div>
</template>

<script setup lang="ts"></script>
