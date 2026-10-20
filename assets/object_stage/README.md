# 柜台共享模型

`counter_geometry.res` 由项目现有建模配方离线生成，包含商店固定陈设、4 档字牌、服务印台和全部 39 件遗物。只保存共享网格和材质；库存、价格、选择状态、灯光和文字仍由运行时提供。

重建：`godot --headless --path . res://src/tools/bake_counter_geometry.tscn`。

验证：`godot --headless --path . res://tests/counter_geometry_test.tscn`，逐件比较烘焙前后的网格数组、变换、材质参数和边界。此次 124 项检查通过，几何与原配方一致，因此保留原有遗物图标并更新其清单中的配方文件摘要。
