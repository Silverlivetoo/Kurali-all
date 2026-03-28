# Git 协作指南

## 查看其他分支的代码

### 查看 yuanbao 分支的代码
```bash
git checkout yuanbao
```

### 查看 wudao-bot 分支的代码
```bash
git checkout wudao-bot
```

### 查看 silverkurali-bot 分支的代码
```bash
git checkout silverkurali-bot
```

## Git 认证配置

由于 SilverKurali 提供了私人令牌，可以使用以下方式配置认证：

1. 设置 credential helper：
```bash
git config credential.helper 'store'
```

2. 创建或编辑 `.git-credentials` 文件（在仓库根目录或用户主目录）：
```
https://AY77-OP:c46bbc064ac8448e0653c0b1b5b005c5@gitee.com
```

3. 验证认证：
```bash
git push origin <branch-name>
```

## 分支切换顺序建议

为了最佳协作体验，建议按照以下顺序查看：

1. 首先查看 yuanbao 分支（基础架构）
2. 然后查看 wudao-bot 分支（功能开发）
3. 最后查看 silverkurali-bot 分支（测试和配置）

## 注意事项

- 切换分支时可能会改变工作区文件
- 每次切换分支后，运行 `git status` 查看文件变化
- 不要在同一分支上进行协作冲突的操作