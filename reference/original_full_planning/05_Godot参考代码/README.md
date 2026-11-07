# Godot 4.x 底层代码参考

本目录是**可复制修改的逻辑样例，不是完整可运行游戏**。需要在目标Godot版本中设置场景、Input Map、资源、导航网格、信号连接，实际测试后才能集成。测试环境中无Godot二进制，未执行引擎编译或场景运行。

最先实现 `EventLedger`、`InventoryGrid`、`ChunkStreamer` 和 `NavPortalGraph`。`PopulationDirector` 依赖预先创建的持久人口池，不能被用作无限生成器。`ZombieBrain` 要求子节点 `NavigationAgent3D` 且外部周期性触发 `notice_target` / `hear_sound`；RayCast可见性由感知系统实现。`PowerGridService` 是集中结算样例，不含距离中继范围、传输损耗、电网断线缓存，这些需要按文档实现。

`RiftTransferService` 返回暂存的 `entities` 字典，不自动覆盖世界；生产版必须先保存WAL并获得保存确认，再更新实际世界节点。`ChunkStreamer` 的卸载等待 `on_chunk_snapshot_committed`，严禁在保存完成前释放永久实体状态。

注意：这是参考实现，有多个接口需要依赖项目契约适配；每个脚本独立交给对应Codex模块对话框实施并运行官方Godot语言检查器，不要一次性全粘进现有项目。

Godot官方文档在不同4.x小版本中的方法签名可能变化，所有GDScript示例请让Codex先用当前安装版做语法检查、严格类型检查、节点连接和单场景测试。
