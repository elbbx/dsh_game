extends SceneTree
## Run: godot --headless --path game --script res://tests/PrototypeChecks.gd

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
    var from_cell: Vector2 = game.player_cell
    var projected: Vector2 = game.cell_to_screen(Vector2(4.0, 7.0))
    if game.screen_to_cell(projected).distance_to(Vector2(4.0, 7.0)) > 0.001:
        _fail("Isometric inverse mismatch")
        return
    game._transition(true)
    await create_timer(0.45).timeout
    if not game.inside:
        _fail("Door did not change to independent interior")
        return
    game.player_cell = Vector2(7.0, 5.0)
    game._interact()
    if not game.loot_claimed or game.scrap != 3 or game.bandages != 3:
        _fail("Interior loot pickup failed")
        return
    game.player_cell = Vector2(2.0, 7.0)
    game._transition(false)
    await create_timer(0.45).timeout
    if game.inside or game.player_cell.distance_to(from_cell) > 0.01:
        _fail("Returning outdoor did not restore player position")
        return
    game._save_game()
    game.scrap = 9999
    game.loot_claimed = false
    game._load_game()
    if game.scrap != 3 or not game.loot_claimed:
        _fail("Save/load state mismatch")
        return
    print("TEST_PASS: iso math; exterior->interior; loot; exit; save/load")
    quit(0)
