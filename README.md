# 仔仔塔防—森林篇

造世界编辑器游戏玩法源码与迁移底板。基线：**2026-11-06 已保存、用户已发布的森林版本**，包含最后的全职业攻击转身和屏障路线拦截修正。

## 换电脑使用

1. 安装造世界编辑器（此快照来自 1.0.0）和 Python 3.10+；登录原来的编辑器账号，让资产库同步完成。
2. 下载本仓库，或 `git clone https://github.com/eiddiedev/zaizaitafang.git`。
3. 在编辑器新建一个**用于恢复的空工程**，保存一次，记下工程目录，然后完全退出编辑器。
4. 在仓库目录执行下列命令，把路径替换成该空工程实际目录：

```sh
python3 tools/transfer.py verify
python3 tools/transfer.py install --project "/path/to/new-editor-project"
python3 tools/transfer.py install --project "/path/to/new-editor-project" --apply --editor-closed
```

Windows 可用 `py -3` 替代 `python3`。第二条仅检查，第三条才安装；会先在工程旁创建带时间戳的备份。目标必须已有 `project.json` 和 `scene.data`。macOS 本机工程通常位于 `~/Library/Application Support/AI World Creator/projects/`，**不要照抄旧电脑工程 ID**。Windows 请使用编辑器实际创建的工程目录。

5. 重新打开目标工程，等待引用资源下载，保存一次，再点本地运行。

`scene/forest.scene.data` 是编辑器已保存的项目场景快照，**不是可以拖入资产库的 .mix**。它保留玩法节点、脚本挂载、模板引用、界面和森林地形。只复制 Lua 到一个空地图不能自动生成这些绑定，所以提供完整底板恢复。安装不复制原世界的发布 ID、账号数据或发布配置，也不会修改已经发布的世界。

**依赖与验证边界：**代码和场景引用已完整校验；怪物、塔、武器、UI、声音等 GLB/音频仍由编辑器云端资源加载，不是离线独立游戏。需要同账号资产权限和网络。已在临时工程验证文件恢复、备份和脚本一致性；尚未在第二台真实电脑验证编辑器下载与运行。不同编辑器版本可能需要重新保存或重新绑定资源。

## 当前玩法

- 1–3 人协作，团队共享金币与塔位，中途加入可建造、升级；多人拆塔走现有确认规则。
- 战士、弓箭手、法师：自动装备武器及职业装饰、普攻、职业技能、大招和闪现。
- 六类塔：连弩、魔法、炮塔、控制、阻挡、经济；每类一至三阶，四阶 A/B 两个分支，共 30 种形态。
- 12 类怪物与骨骼动作、受击反馈、音效、图鉴、复活倒计时、波次间恢复。
- 24 波主线；通关后可进入无限模式，包含 25–60 波的设计。排行榜保存最高通过波次，局内成长不跨局保存。
- 森林 64×64 地图，当前 **11 个塔位**；原生角色移动、拖拽回位镜头和双指缩放。

## 代码入口

| 内容 | 文件 |
| --- | --- |
| 数值、费用、英雄、怪物、波次 | `scripts/modules/config_9.lua` |
| 战斗状态机、伤害、经济、多人规则 | `scripts/modules/simulation_9.lua` |
| 路线、塔位、出生点、地形采样、镜头边界 | `scripts/modules/layout_9.lua` |
| 主控、网络快照、原生移动、排行榜 | `scripts/modules/runtime-host_9.lua` |
| UI、镜头交互、图鉴、建塔面板 | `scripts/modules/ui_31.lua` |
| 塔、攻击特效与音效路由 | `scripts/modules/ms-armory_9.lua` |
| 怪物模型、骨骼动画与血条 | `scripts/modules/ms-foes_9.lua` |
| 英雄持武器、转身和动作 | `scripts/modules/imported/prefab_2/d7508e1d-05a6-42d1-a7c8-5da9fd60d9b7.lua` |
| 英雄动作时间线 | `scripts/modules/imported/prefab_2/19bdbb99-c5cc-4c8a-b21c-3d6c45f73025.lua` |
| 职业服装 | `scripts/modules/imported/prefab_3/36a0d6b8-55ee-434f-ae5a-a9d3ba51a3e2.lua` |
| 精确脚本挂载和校验 | `manifest.json` |
| 场景节点名称、资源 ID/URI | `bindings/scene-roots.json`、`bindings/assets.json` |

不要删除 `---@id`、`---@referenceName`、`---@assetRef`，不要随意改绑定节点名称，也不要清理场景上方的模板。它们被玩法按名称查找。旧资源保留是为了确保模型、武器、音效与特效不丢失。

## 开发与测试

```sh
python3 -m venv .venv
# macOS/Linux
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python tests/run.py
# Windows: 使用 .venv\Scripts\python.exe 执行上述 Python 命令
```

迁移后修改目标工程里的脚本，在编辑器保存，再导出新的已保存版本回仓库：

```sh
python3 tools/export_project.py --project "/path/to/editor-project"
python3 tools/transfer.py verify
```

导出器只取场景实际引用的脚本，脚本与场景未同步时会拒绝导出。不会导出 Agent 对话、账号配置、发布世界 ID、缓存或开发机器路径。内嵌的 `official` 和 `runtime-builtin` 文件用于保留编辑器运行依赖，不代表本仓库重新授权这些平台组件。

新地图接入见 [地图与资源接入](docs/new-map.md)，测试与迁移说明见 [验收](docs/verification.md)。
