extends SceneTree
## Run: godot --headless --path game --script res://tests/PrototypeChecks.gd
##
## S0 回归：等距数学、室外→室内、搜刮、离开、存读档、近战击杀、死亡重开，
## 以及 doc/独立室内切换与建筑.md 的「同模板双屋不串库存」验收。

func _initialize() -> void:
    call_deferred("_run_checks")

func _fail(message: String) -> void:
    printerr("TEST_FAIL: " + message)
    quit(1)

func _run_checks() -> void:
    var packed: PackedScene = load("res://scenes/main.tscn")
    if packed == null:
        _fail("Cannot load main scene")
        return
    var game: Variant = packed.instantiate()
    root.add_child(game)
    await process_frame
    if game.inside:
        _fail("Expected initial outdoor state")
        return
    if game.HOUSES.size() != 2 or String(game.HOUSES[0]["template"]) != String(game.HOUSES[1]["template"]):
        _fail("Expected two houses sharing one template")
        return
    var from_cell: Vector2 = game.player_cell
    var projected: Vector2 = game.cell_to_screen(Vector2(4.0, 7.0))
    if game.screen_to_cell(projected).distance_to(Vector2(4.0, 7.0)) > 0.001:
        _fail("Isometric inverse mismatch")
        return

    # --- House A: enter, loot, leave ---
    game._transition(true, "BLD_A")
    await create_timer(0.45).timeout
    if not game.inside or game.active_house_id != "BLD_A":
        _fail("Door did not change to independent interior of BLD_A")
        return
    game.player_cell = Vector2(7.0, 5.0)
    game._interact()
    if not bool(game.room_states["BLD_A"]["loot_claimed"]) or game.scrap != 3 or game.bandages != 3:
        _fail("Interior loot pickup failed in BLD_A")
        return
    game.player_cell = Vector2(2.0, 7.0)
    game._transition(false)
    await create_timer(0.45).timeout
    if game.inside or game.player_cell.distance_to(from_cell) > 0.01:
        _fail("Returning outdoor did not restore player position")
        return

    # --- House B (same template): its loot must be INDEPENDENT, not shared ---
    if bool(game.room_states["BLD_B"]["loot_claimed"]):
        _fail("Same-template house B inherited house A's loot flag")
        return
    game.player_cell = Vector2(19.0, 17.0)   # B's exterior door anchor
    game._interact()
    await create_timer(0.45).timeout
    if not game.inside or game.active_house_id != "BLD_B":
        _fail("Second house door did not open its own interior")
        return
    game.player_cell = Vector2(7.0, 5.0)
    game._interact()
    if not bool(game.room_states["BLD_B"]["loot_claimed"]) or game.scrap != 6:
        _fail("House B loot did not grant its own crate")
        return

    # Killing B's interior zombie must not affect A's interior zombie.
    game.player_cell = Vector2(8.0, 4.0)
    for i in range(3):
        game.attack_cooldown = 0.0
        game._attack()
    if float(game.room_states["BLD_B"]["interior_zombies"][0]["hp"]) > 0.0:
        _fail("Could not kill interior zombie in BLD_B")
        return
    if float(game.room_states["BLD_A"]["interior_zombies"][0]["hp"]) != 40.0:
        _fail("Killing in B damaged A's interior zombie (state leak)")
        return

    game.player_cell = Vector2(2.0, 7.0)
    game._transition(false)
    await create_timer(0.45).timeout

    # Re-entering A must NOT respawn loot or duplicate scrap.
    game.player_cell = Vector2(14.0, 12.0)
    game._interact()
    await create_timer(0.45).timeout
    if game.active_house_id != "BLD_A":
        _fail("Re-entering house A failed")
        return
    game.player_cell = Vector2(7.0, 5.0)
    game._interact()
    if game.scrap != 6:
        _fail("Re-entering a looted house duplicated scrap")
        return
    game.player_cell = Vector2(2.0, 7.0)
    game._transition(false)
    await create_timer(0.45).timeout

    # --- Save / load round trip must preserve per-house room states ---
    game._save_game()
    game.scrap = 9999
    game.room_states["BLD_A"]["loot_claimed"] = false
    game._load_game()
    if game.scrap != 6 or not bool(game.room_states["BLD_A"]["loot_claimed"]):
        _fail("Save/load did not restore per-house loot state")
        return
    if not bool(game.room_states["BLD_B"]["loot_claimed"]):
        _fail("Save/load lost house B loot state")
        return

    # --- Melee kill on an outdoor zombie ---
    game.player_cell = Vector2(5.0, 15.0)
    for i in range(4):
        game.attack_cooldown = 0.0
        game._attack()
    if float(game.zombies[0]["hp"]) > 0.0:
        _fail("Melee attacks did not kill the outdoor zombie")
        return

    # --- Death + restart: reset fields, keep save file loadable ---
    game.player_hp = 0.0
    game.hour = 22.0
    game.bandages = 0
    game.scrap = 77
    game._reset_run()
    if game.inside or game.player_hp != 100.0 or game.scrap != 0 or game.bandages != 2:
        _fail("New run did not reset player/world state")
        return
    if game.player_cell.distance_to(Vector2(7.0, 9.0)) > 0.001:
        _fail("New run did not restore the starting cell")
        return
    if float(game.zombies[0]["hp"]) != 55.0:
        _fail("New run did not respawn the initial zombie population")
        return
    if bool(game.room_states["BLD_A"]["loot_claimed"]) or bool(game.room_states["BLD_B"]["loot_claimed"]):
        _fail("New run did not reset room states")
        return
    game.scrap = 1234
    game._load_game()
    if game.scrap != 6:
        _fail("New run destroyed the saved game")
        return

    # --- Repeated entry/exit stress: 100 transitions must keep state stable ---
    # Drive _set_space directly (no tween delay) so the full loop stays well
    # inside QA's per-command timeout while still exercising the state logic.
    for i in range(100):
        game.player_cell = Vector2(14.0, 12.0)
        game._set_space(true, "BLD_A")
        if not game.inside or game.active_house_id != "BLD_A":
            _fail("Stress iteration %d failed to enter" % i)
            return
        game.player_cell = Vector2(2.0, 7.0)
        game._set_space(false, "")
        if game.inside:
            _fail("Stress iteration %d failed to exit" % i)
            return
    if game.scrap != 6 or not bool(game.room_states["BLD_A"]["loot_claimed"]):
        _fail("100 transitions changed loot state")
        return

    # --- Locked door: U toggles only the nearby house; E must be refused ---
    game.player_cell = Vector2(14.0, 12.0)
    game._toggle_door_lock()
    if not bool(game.room_states["BLD_A"]["door_locked"]):
        _fail("U did not lock the nearby house door")
        return
    if bool(game.room_states["BLD_B"]["door_locked"]):
        _fail("Locking BLD_A leaked to BLD_B")
        return
    game._interact()
    if game.inside:
        _fail("Locked door still allowed entry")
        return
    game._toggle_door_lock()
    if bool(game.room_states["BLD_A"]["door_locked"]):
        _fail("U did not unlock the door")
        return

    # --- Transition mutual exclusion: a second transition is a no-op ---
    game._transition(true, "BLD_A")
    if not game.transitioning:
        _fail("Transition lock was not set")
        return
    game._attack()
    game._save_game()
    game._transition(false, "")
    await create_timer(0.45).timeout
    if not game.inside or game.active_house_id != "BLD_A":
        _fail("Re-entrant transition broke the in-progress one")
        return

    # --- Space load failure: rollback keeps the original space and position ---
    var cell_before: Vector2 = Vector2(7.0, 5.0)
    game.player_cell = cell_before
    game.space_load_fail_next = true
    game._transition(false, "")
    await create_timer(0.45).timeout
    if not game.inside or game.player_cell.distance_to(cell_before) > 0.001:
        _fail("Failed space load did not roll back")
        return

    # --- Blocked exit: fallback to nearest legal empty outdoor cell ---
    game.player_cell = Vector2(2.0, 7.0)
    game.outdoor_saved_cell = Vector2(5.0, 15.0)  # occupied by outdoor zombie[0]
    game.zombies[0]["pos"] = Vector2(5.0, 15.0)
    game.zombies[0]["hp"] = 55.0
    if not game._is_outdoor_cell_blocked(Vector2(5.0, 15.0)):
        _fail("Blocked-cell detection failed")
        return
    game._set_space(false, "")
    if game.inside:
        _fail("Exit did not leave the interior")
        return
    if game._is_outdoor_cell_blocked(game.player_cell) or not game._walkable(game.player_cell):
        _fail("Exit fallback placed player in a blocked/wall cell")
        return
    if game.player_cell.distance_to(Vector2(5.0, 15.0)) < 0.001:
        _fail("Exit fallback did not move away from the blocked anchor")
        return

    # --- save/load preserves door locks per house (v3+ format) ---
    game.room_states["BLD_B"]["door_locked"] = true
    game._save_game()
    game.room_states["BLD_A"]["door_locked"] = false
    game.room_states["BLD_B"]["door_locked"] = false
    game._load_game()
    if not bool(game.room_states["BLD_B"]["door_locked"]):
        _fail("save/load lost BLD_B door lock")
        return
    if bool(game.room_states["BLD_A"]["door_locked"]):
        _fail("save/load leaked door lock to BLD_A")
        return

    # --- SurvivalStats: fixed-step, frame-rate independent progression ---
    # Two different delta sequences covering the same total time must produce
    # the same tick count and the same stat values (M02 acceptance).
    var s1: SurvivalStats = SurvivalStats.new()
    var s2: SurvivalStats = SurvivalStats.new()
    var total: float = 10.0
    # Use exact loop counts so both sequences cover precisely the same total
    # time (avoids floating-point loop-bound drift skewing the tick count).
    for i in range(600):        # 60 fps-ish: 600 x 1/60 = 10.0 s
        s1.advance(1.0 / 60.0)
    for i in range(100):        # 10 fps-ish: 100 x 0.1 = 10.0 s
        s2.advance(0.1)
    if s1.clock_ticks != s2.clock_ticks:
        _fail("Fixed-step clock depends on frame rate (%d vs %d ticks)" % [s1.clock_ticks, s2.clock_ticks])
        return
    if abs(s1.hunger - s2.hunger) > 0.0001 or abs(s1.thirst - s2.thirst) > 0.0001:
        _fail("Survival stats diverge across frame rates")
        return
    var expected: int = int(total / SurvivalStats.STEP_SECONDS)
    if absi(s1.clock_ticks - expected) > 1:
        _fail("Unexpected tick count for fixed step (%d, expected ~%d)" % [s1.clock_ticks, expected])
        return
    # Boundary clamping
    s1.hunger = 999.0
    s1.fatigue = -50.0
    s1.clamp_all()
    if s1.hunger != 100.0 or s1.fatigue != 0.0:
        _fail("Stat clamping failed")
        return
    # to_dict / from_dict round trip preserves the clock
    var snap: Dictionary = s1.to_dict()
    var s3: SurvivalStats = SurvivalStats.new()
    s3.from_dict(snap)
    if s3.clock_ticks != s1.clock_ticks or abs(s3.hunger - s1.hunger) > 0.0001:
        _fail("SurvivalStats snapshot round trip failed")
        return

    # --- Save/load v4 preserves stats clock and values ---
    game.player_hp = 73.0
    game.hunger = 41.0
    game.stats.thirst = 22.0
    game.stats.clock_ticks = 137
    game._save_game()
    game.player_hp = 1.0
    game.hunger = 99.0
    game.stats.thirst = 0.0
    game.stats.clock_ticks = 0
    game._load_game()
    if int(game.player_hp) != 73 or int(game.hunger) != 41 or int(game.stats.thirst) != 22 or game.stats.clock_ticks != 137:
        _fail("v4 save/load did not restore SurvivalStats")
        return
    # Stats must survive a space transition (no reset on enter/exit)
    var ticks_before: int = game.stats.clock_ticks
    game.player_cell = Vector2(14.0, 12.0)
    game._transition(true, "BLD_A")
    await create_timer(0.45).timeout
    game.player_cell = Vector2(2.0, 7.0)
    game._transition(false, "")
    await create_timer(0.45).timeout
    if game.stats.clock_ticks < ticks_before:
        _fail("SurvivalStats clock reset on space transition")
        return

    # --- Consumables: normalized table + use effects on SurvivalStats ---
    if game.consumables.load_error != "":
        _fail("Consumables table failed to load: " + game.consumables.load_error)
        return
    if not game.consumables.has_item("ITM_0001") or not game.consumables.has_item("ITM_0065"):
        _fail("Normalized consumables table missing food/water entries")
        return
    if float(game.consumables.effect_of("ITM_0001").get("hunger", 0.0)) >= 0.0:
        _fail("Food effect must reduce hunger")
        return
    if float(game.consumables.effect_of("ITM_0065").get("thirst", 0.0)) >= 0.0:
        _fail("Water effect must reduce thirst")
        return
    # Unknown id / zero stock are rejected without mutating state
    var pack_before: int = game.consumables.total_count()
    if game.consumables.consume("NOT_AN_ITEM", game.stats):
        _fail("Unknown item id was consumed")
        return
    if game.consumables.total_count() != pack_before:
        _fail("Rejected consume mutated inventory")
        return
    # Loot granted food + water in both houses
    if game.consumables.count("ITM_0001") < 1 or game.consumables.count("ITM_0065") < 1:
        _fail("Loot did not grant consumables")
        return
    # Eat: hunger drops and one food is removed (clamped at 0)
    game.hunger = 60.0
    game.stats.hunger = 60.0
    var food_before: int = game.consumables.count("ITM_0001")
    game._consume_for("hunger")
    if game.hunger >= 60.0 or game.consumables.count("ITM_0001") != food_before - 1:
        _fail("Eating did not reduce hunger or consume one food")
        return
    # Drink: thirst drops and one water is removed
    game.stats.thirst = 70.0
    var water_before: int = game.consumables.count("ITM_0065")
    game._consume_for("thirst")
    if game.stats.thirst >= 70.0 or game.consumables.count("ITM_0065") != water_before - 1:
        _fail("Drinking did not reduce thirst or consume one water")
        return
    # clamp: hunger cannot go below 0 even with repeated consumption is impossible
    # here (stock limited), so verify the pure-data clamp directly
    game.stats.hunger = 5.0
    game.consumables.add("ITM_0001", 5)
    game.stats.hunger = 5.0
    game._consume_for("hunger")
    if game.stats.hunger < 0.0 or game.stats.hunger > 100.0:
        _fail("Consumable effect broke hunger clamp")
        return
    # v5 save/load preserves inventory and stats
    game._save_game()
    var inv_snapshot: Dictionary = game.consumables.inventory_to_dict()
    game.consumables.inventory.clear()
    game._load_game()
    if game.consumables.inventory_to_dict() != inv_snapshot:
        _fail("v5 save/load lost consumables inventory")
        return
    # Inventory survives a space transition (no reset)
    var pack_after_transition: int = game.consumables.total_count()
    game.player_cell = Vector2(14.0, 12.0)
    game._transition(true, "BLD_A")
    await create_timer(0.45).timeout
    game.player_cell = Vector2(2.0, 7.0)
    game._transition(false, "")
    await create_timer(0.45).timeout
    if game.consumables.total_count() != pack_after_transition:
        _fail("Consumables inventory reset on space transition")
        return

    print("TEST_PASS: iso math; 2 independent houses; loot/exit; save/load v1-v5; melee kill; death restart; 100x transitions; locked door; transition mutex; load-fail rollback; blocked-exit fallback; SurvivalStats fixed-step; consumables table/use/clamp/save")
    quit(0)
