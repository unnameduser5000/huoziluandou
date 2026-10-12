# C3 日志取材与审查说明

2026-10-12。用户确认以今天最新C3原型为主，并要求补充选择理由、逐步迭代表现及适量图片。

## 事实来源

- 用户本次直接补充：转向源于与队友交流，队友提出更有趣、符合涌现思路的4×4战斗玩法；先确定战斗方向，再逐步发展出当前大循环。该说明是转向动机与创意归属的首要依据，替代此前由旧笔记推断转向起点的写法。
- 用户本地Obsidian项目笔记《TapTap 发布草稿/第五次记录.md》：循环已实现但不好玩、随机性/变数/挑战不足；短期压力与长期收益；回到肉鸽方向。此为动机来源，不能据此虚构详细会议决策。
- 已跟踪Godot项目README与提交679cdd5：4×4拼词战斗及三种大循环。此为历史背景，不把其功能视为C3已集成。
- mockups/map/index.html：第一轮5方向→第二轮A/B/C→C2→C3的明确迭代索引；页面标C3为当前主推。
- mockups/map/plate_route.html/js：C2铺字、目标字、行动点和地图词归属。
- prototype_c3/src/plate_collect.html/js、plate.js：当前权威玩法，10×7地图、6×6排版、敌人看守、首次词回墨、模拟损血和幕终边界。
- “为何选择C3”的段落为对上述规则差异的设计分析，不冒充已记录的会议原话或已验证玩家偏好。

## 校正重点

C3使用字匣与横竖2～4字识词，不是Godot字袋抽取、4×4转弯连线。fight()直接模拟损血，气血最低1，没有完整回合战斗/死亡压力；敌词状态仅在界面展示并通过计数影响公式。幕终下一幕与余墨转金尚未执行。

最新源文件存在guardOf()规则，比mockups旧副本更新：敌人邻字受看守，不能战前拾取拆词。当前首领战后终止流程，不能声称已实现三幕。商店与伏击使用Math.random，不承诺固定种子复现。

## 验证与图片

内置CUA/node_repl运行环境无法启动后，使用本机独立无头Edge＋Playwright加载原文件。未注入游戏资源、未篡改状态，实际点击初始字与排版格：火(0,1)、力(1,1)、合(1,0)，得到交汇火力/合力，墨14→16；收回并重放火不重复奖励；走到相邻格后墨16→15。70地图格、36排版格，1440px宽无水平溢出，三页面无pageerror。该检查不等同于完整胜率/跨幕验收。

1. 01-iteration-options.png：mockups/map/index.html完整方案索引，历史页面原样；部分文案未更新，正文说明。
2. 02-c2-route.png：mockups/map/plate_route.html初始状态，历史原型。
3. 03-c3-start.png：prototype_c3/src/plate_collect.html初始状态，随包提供备用，不在正文重复展示。
4. 04-c3-crosswords-scout.png：当前C3普通界面操作后形成火力/合力，点击远处首领侦察；没有移动/跳关/作弊。

四张图片均为2026-10-12新拍实际HTML渲染，无AI生成、无旧版冒充、无图像合成。日志正文使用3张，便于比较方案索引、C2和C3。PNG与Markdown同目录关系可离线查看。

本次只提交新日志、审查记录和配图。现有未跟踪mockups/、prototype_c3/由其他工作产生，本次不冒领或混入文档提交；以文件哈希记录审查对象。没有向TapTap或博客发布。

## 本次追加的溯源结论

- 用户确认本地两个目录：huoziluandou 是队友原工程；Huozi 是依据所提供 PDF 独立重建的一次实现。已读取“根据策划案开发游戏”对话确认来源。未把独立实现归为队友最早的实机版本。
- 原策划图来自 project/docs/images/board.png，GDD 第3章引用同图。它证明设计形式，不是实机截图。原工程最早提交 f5fe1ff（2026-10-10）；未找到能确认当时拍摄的独立初版实机截图。
- 既有实机截图来自 gen/work/ui-*.png；tests/ui_test.gd 记录其生成流程。奖励、商店、目标沙盘等部分属于设置状态后的界面测试，不证明自然通关或数值平衡。
- 当前原工程补拍使用外部 SceneTree 脚本，仅加载现有场景、调用已有开局和路由、在内存切换主题；未重置仓库、修改游戏源码、写入主题设置。三张补拍为 current-godot-paper/neon/map.png。
- 曾将历史提交解包到独立 work/history 目录尝试复现；用户指明应使用本地实现后，不再采用这些复现画面。它们未纳入本次日志、附件和提交。
- Godot 控制台当前加载61字、137词；README/GDD 的106词是早期文档口径，不把它当成当前内容总数。未重新运行完整游戏验收，本任务只做文档与画面审查。
- GDD V1.0“合击”表述与后续现有代码不同：当前为登记词后统一发动。正文明确区分初始策划机制与后续交互发展。
- Git 提交能证明修改内容及日期，不证明所有人的创意贡献，也不证明UI尝试是由玩家测试择优选出。

## 原型源文件与截图 SHA-256

- `prototype_c3/src/plate_collect.js`：`c2d45159644ee9c8c1f539e8f0079f8ce14527622c266f1f41a37cf6c9abd91c`
- `prototype_c3/src/plate_collect.html`：`f37e2a746341d8e06a03396a129260a35971c017e545c236c9a2158ddf2dec7b`
- `prototype_c3/src/plate.js`：`3c626b980640fe938a59539aebab1832551c15d2f8d8489cb9364830c17ff28e`
- `docs/devlogs/images/c3/01-iteration-options.png`：`abc9b37757c53967d17984cf4f3696d5f153577890406b687e4b4768d9d21a1a`
- `docs/devlogs/images/c3/02-c2-route.png`：`97da3ad9ad39b325955337f7ee8086108953068349094dce2ad1e79e0f67a784`
- `docs/devlogs/images/c3/03-c3-start.png`：`c2386a15bbbef500f875e3c5cc68a58942415aad9e3443be79aa8ab006fe6379`
- `docs/devlogs/images/c3/04-c3-crosswords-scout.png`：`c8c7657dcdb69e9520846f739e4738dd45a642af8678975eb179570683f36c29`
- `docs/devlogs/images/c3/05-original-gdd-board.png`：`dd9d9230f041fdbc559f6cbc5155ce3ee00a1fc8ba823f368ff60d1a1518678d`
- `docs/devlogs/images/c3/06-existing-huozi-battle.png`：`fbe7afe8f110be048cb101f480218b157955c411a82dd16e9ec1cc230360a523`
- `docs/devlogs/images/c3/07-existing-huozi-lab.png`：`0869ec893868ea77de5cdf32a94bbc10bc5feaea62ef0593d2b9d04c68cca993`
- `docs/devlogs/images/c3/08-existing-huozi-reward.png`：`c2f97af303867b0750421911853f0d0f7d9b61ef39d9e5f83bddbfa3614475e4`
- `docs/devlogs/images/c3/09-existing-huozi-shop.png`：`ba5b874e44d992a62ef8494708cf8f98da84a52ad3478c2c9812a8d452b4aec1`
- `docs/devlogs/images/c3/10-existing-huozi-map.png`：`987569cec070dfcec23b6803d8449d39a8764f7e45ed13b7242c8bfc07fa0da7`
- `docs/devlogs/images/c3/11-original-glyph-network.png`：`119cfb9f841ff43f268d3a0442f1f29778df366e68dc82685ff46944d4e4f6a9`
- `docs/devlogs/images/c3/current-godot-map.png`：`f8c1a47166723fffa812dc51fcf86b91f697f7f877993e0e79346b26bc1c16ca`
- `docs/devlogs/images/c3/current-godot-neon.png`：`657ff4bf49869f36397d1894f9cdbc936a75fd7b4bbb873304f79397a28a125c`
- `docs/devlogs/images/c3/current-godot-paper.png`：`2a704ad54a88b7b340e6b82746bf4ab4a1d5f78eecf07f2cbaee5193fb52dfdc`
