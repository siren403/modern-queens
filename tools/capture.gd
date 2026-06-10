extends Node

@export var scene_path: String = "res://scenes/main.tscn"
@export var out_path: String   = "user://capture.png"
@export var warmup_frames: int = 5

func _ready() -> void:
    add_child((load(scene_path) as PackedScene).instantiate())
    for _i in warmup_frames:
        await get_tree().process_frame
    await RenderingServer.frame_post_draw
    var img: Image = get_viewport().get_texture().get_image()
    img.save_png(out_path)
    print("[capture] saved -> ", ProjectSettings.globalize_path(out_path))
    get_tree().quit()
