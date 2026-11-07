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

    # Combat: repeated attacks must kill a zombie, and a dead zombie must
    # stop being a threat (hp <= 0 is filtered by _process_zombies/_attack).
    game.player_cell = Vector2(5.0, 15.0)
    for i in range(4):
        game.attack_cooldown = 0.0
        game._attack()
    var outdoor_zombie: Dictionary = game.zombies[0]
    if float(outdoor_zombie["hp"]) > 0.0:
        _fail("Melee attacks did not kill the zombie")
        return

    # Death + restart: force lethal damage, then restart and verify every
    # run-level field is reset while the save file remains loadable.
    game.player_hp = 0.0
    game.hour = 22.0
    game.bandages = 0
    game.scrap = 77
    game.loot_claimed = true
    game._reset_run()
    if game.inside or game.player_hp != 100.0 or game.scrap != 0 or game.bandages != 2 or game.loot_claimed:
        _fail("New run did not reset player/world state")
        return
    if game.player_cell.distance_to(Vector2(7.0, 9.0)) > 0.001:
        _fail("New run did not restore the starting cell")
        return
    if float(game.zombies[0]["hp"]) != 55.0:
        _fail("New run did not respawn the initial zombie population")
        return
    game.scrap = 1234
    game._load_game()
    if game.scrap != 3:
        _fail("New run destroyed the saved game")
        return

    print("TEST_PASS: iso math; exterior->interior; loot; exit; save/load; melee kill; death restart; save survives restart")
    quit(0)
