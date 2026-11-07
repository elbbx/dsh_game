# AGENTS.md — Way to Home / Godot 单人3D生存项目

## Read first
- `docs/design-kit/00_开始这里/原始完整规划_106章.md`
- `docs/design-kit/01_Codex多对话框流程/接口契约.md`
- `docs/design-kit/00_开始这里/模块依赖表.csv`
- Current module only: `docs/design-kit/02_模块独立规格/Mxx_*.md`

## Guardrails
1. Godot 4.x; respect actual installed API version. Treat existing project code as source of truth for implementation state, game plans as source of truth for desired requirements.
2. Implement only approved module scope; avoid touching unrelated modules or renaming stable interfaces.
3. Do not pause gameplay when inventory/radial/HUD/medical menu is open; movement & sprint remain available.
4. Three total equipped weapon slots shared between ranged and melee. Six quick categories: 1 ranged,2 melee,3 tools,4 medicine,5 food/drink,6 vision. Except tools, quick access may not pull items from main backpack.
5. Global status: 7 stats; six always-visible status rings in bottom-left, stamina circle beside player only when expended plus one-second retention; temporary hot/cold/disease rings.
6. All durable entities have one persistent instance ID. Double-world shares buildings, items, constructed structures, and alterations. Enemies are layer-specific; vehicles exist in one active layer only.
7. A visible enemy spawn must never occur spontaneously in player view. Spawning activates preexisting population IDs and respects safehouse zones, per-chunk caps, camera LOS, NavMesh and cooldown.
8. Pathing: global chunk portal graph, local NavigationAgent3D/NavMesh, door/window/stair link metadata. Do not teleport enemies or NPCs to hide navigation failure.
9. Scene-tree updates on main thread. Async prepare immutable data; guard against stale results with generation tokens.
10. Transactions use event_id idempotency; an item belongs to exactly one inventory/world location. Persist with schema version, WAL/snapshot and save migration.
11. Each task: inspect → plan → small code change → tests → logs → handoff. Never claim Godot run/test success without executing it.
12. Document tradeoffs, bugs, dependencies and changed files. Obtain approval before changing public interface contracts or removing modules.

## Output format for every implementation
- Files changed; runtime/scene wiring; data schemas; test command+observed output; performance results if applicable; open issues; integration risks.
