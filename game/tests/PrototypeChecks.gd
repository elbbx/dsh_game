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

    # --- v3 save/load preserves door locks per house ---
    game.room_states["BLD_B"]["door_locked"] = true
    game._save_game()
    game.room_states["BLD_A"]["door_locked"] = false
    game.room_states["BLD_B"]["door_locked"] = false
    game._load_game()
    if not bool(game.room_states["BLD_B"]["door_locked"]):
        _fail("v3 save/load lost BLD_B door lock")
        return
    if bool(game.room_states["BLD_A"]["door_locked"]):
        _fail("v3 save/load leaked door lock to BLD_A")
        return

    print("TEST_PASS: iso math; 2 independent houses; loot/exit; save/load v1-v3; melee kill; death restart; 100x transitions; locked door; transition mutex; load-fail rollback; blocked-exit fallback")
    quit(0)
