# 协作查看指南

## 如何查看其他分支的代码

### 1. 查看 yuanbao 分支的代码
```bash
git checkout yuanbao
```

yuanbao 分支包含：
- OpenClaw 工作空间配置
- README.md（项目说明）
- 多种技能文件

### 2. 查看 wudao-bot 分支的代码
```bash
git checkout wudao-bot
```

wudao-bot 分支包含：
- OpenClaw 工作空间配置
- CONTRIBUTORS.md（贡献者文档）
- 多种技能文件

### 3. 查看 silverkurali-bot 分支的代码
```bash
git checkout silverkurali-bot
```

silverkurali-bot 分支包含：
- OpenClaw 工作空间配置
- README.md（项目说明）
- TESTING.md（测试指南）
- 多种技能文件

## 查看差异的方法

### 查看分支差异
```bash
# 查看 yuanbao 和 wudao-bot 的差异
git diff yuanbao wudao-bot

# 查看 yuanbao 和 silverkurali-bot 的差异
git diff yuanbao silverkurali-bot

# 查看 wudao-bot 和 silverkurali-bot 的差异
git diff wudao-bot silverkurali-bot
```

### 查看文件差异
```bash
# 查看某个文件的差异
git diff yuanbao wudao-bot CONTRIBUTORS.md
```

## 协作建议

1. **定期同步**：每周至少查看一次其他分支的更新
2. **代码审查**：查看对方的提交历史和代码变更
3. **问题反馈**：发现问题时及时沟通
4. **合并策略**：通过 Pull Request 方式合并代码，确保质量

## 远程仓库访问

仓库地址：https://gitee.com/AY77-OP/kurali-all

可以使用以下命令查看远程分支：
```bash
git fetch origin
git branch -r
```

## 分支管理

目前已有三个分支：
- yuanbao（元宝）
- wudao-bot（無道的Bot）
- silverkurali-bot（SilverKurali的Bot）

每个分支都包含了独特的文档文件，展示了不同的工作重点。