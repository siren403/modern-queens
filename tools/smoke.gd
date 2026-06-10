extends SceneTree

func _initialize() -> void:
    print("[smoke] headless logic OK, frame=", Engine.get_process_frames())
    quit()
