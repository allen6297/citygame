extends Resource
class_name RoadLaneGraph

class LaneData extends Resource:
	var id: int
	var segment_id: int
	var direction: int # 1 or -1
	var index: int
	var width: float
	var points: Array[Vector3] = []
	
class LaneConnection extends Resource:
	var from_lane_id: int
	var to_lane_id: int
	var path_points: Array[Vector3] = []
