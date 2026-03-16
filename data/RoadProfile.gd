extends Resource
class_name RoadProfile

@export var display_name: String
@export var lane_width: float = 3.5
@export var lanes_forward: int = 1
@export var lanes_backward: int = 1
@export var median_width: float = 0.0
@export var sidewalk_left: float = 2.0
@export var sidewalk_right: float = 2.0
@export var curb_size: float = 0.2

@export var supports_zoning: bool = true
@export var carries_water: bool = true
@export var carries_power: bool = true


func get_total_lane_count() -> int:
	return max(lanes_forward, 0) + max(lanes_backward, 0)


func get_roadway_width() -> float:
	return get_total_lane_count() * lane_width + median_width


func get_total_width() -> float:
	return get_roadway_width() + sidewalk_left + sidewalk_right + (curb_size * 2.0)


func has_any_utility() -> bool:
	return carries_water or carries_power
	
