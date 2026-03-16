extends Control

const MainUIRuntimeScript = preload("res://scripts/ui/MainUIRuntime.gd")

@onready var _main_ui: MainUI = $MainUI

var _ui_runtime = MainUIRuntimeScript.new()


func _ready() -> void:
	_ui_runtime.setup(_main_ui)


func _unhandled_input(event: InputEvent) -> void:
	_ui_runtime.handle_unhandled_input(event)
