# 字肆与战后字匣

商店与奖励使用独立 3D 场景承载可选物件。界面只叠加简短价格、当前物件的完整说明和确认操作。其余行旅页面仍使用 `journey/`。

商店后排陈列五张字卡，前排陈列三件随机遗物，右侧保留三种服务；刷新使用左侧小转轮。铜钱标签使用亮米金色与深色描边。旧三卡存档保留库存，刷新后切换到五卡；槽位布局按版本迁移，购买后不挤动其他商品。

## 边界

- `object_stage.gd`：柜台、字匣、陈列字块、服务印台与陈设；独立相机、灯光及物件动作。不访问 GameState 或游戏随机数。店主使用 `assets/characters/shopkeeper/portrait.png` 的透明插画，由 Sprite3D 参与空间遮挡，保持与怪物一致的墨线画法。
- `pigment.gdshader`：限制明暗色阶；阴影连续衰减，避免把阴影采样放大成颗粒。
- `object_stage_view.gd`：私有 World3D / SubViewport，把静止物件边界投影为稳定的二维触控区域。渲染分辨率上限 1600×900，4× MSAA；手机调整机位。
- `glyph_offer.gd`：投影位置上的鼠标、键盘焦点与价格标签。只发出查看 / 点击事件。
- `object_hud.gd` / `readability.gdshader`：共用底部说明与操作，保留长文滚动和手机字号。
- `reward_screen.gd` / `shop_screen.gd`：选择、确认与已有奖励 / 购买规则之间的连接。购买后保留空位；查看不消耗随机数。

选中时抬起物件，确认后取走；奖励进入时打开匣盖。确认期间锁定操作，避免重复结算。设置中的减少动态效果即时停止灯笼及物件动画，并直接完成确认操作。

商店额外构建侧窗格栅、书架、柜台榫接与重复裙板模块，按材质合并网格。独立聚光灯穿过格栅投向柜面，局部灯光能量在距离与阴影衰减后限制上限，保持明暗分区。轻体积雾只在商店开启，奖励字匣仍沿用自己的照明配置。运行文字与交互控件不参与雾和光照。

几何复用庭院的 `mesh_workshop.gd`，描边复用 `ink_outline.gdshader`。轻微木材磨损来自项目已有 `assets/title/courtyard/materials/weathered_planks_diffuse.jpg`，来源与许可见该目录中的来源记录。店主插画的参考、生成工具与完整提示词见 `assets/characters/shopkeeper/README.md`。光照使用本场景独立配置。

## 验证

商店固定陈设、字牌、服务印台和 39 件遗物使用 `assets/object_stage/counter_geometry.res` 的共享网格；标题界面后台预读网格和商店脚本，进入与刷新不再现场执行模型生成配方。灯光、文字、商品价格、选择动画与交互仍由运行时创建。修改模型配方后运行 `godot --headless --path . res://src/tools/bake_counter_geometry.tscn` 重建资源，再运行 `tests/counter_geometry_test.tscn` 对比全部网格数组、变换、材质参数和投影边界。`tests/menu_shop_loading_test.tscn -- --capture` 检查正常动画、减少动态效果下开始冒险后从暂停菜单返回，以及首次和重复进入商店的耗时与完整显示。

`tests/object_stage_test.tscn -- --capture` 验证正常动画、确认防连点、结算、布局、减少动态效果和场景释放；`tests/journey_ui_test.tscn -- --capture` 对照原始固定种子并检查完整界面流程。实机图见 `docs/art-concepts/2026-10-16/object-menus/`。触控区域按 960×432 窗口验证最低 48 屏幕像素；移动设备性能仍需在目标设备测试。
