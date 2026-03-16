extends RefCounted
class_name CityChunkSystem


class RenderChunk extends RefCounted:
	var coord: Vector2i
	var node_ids: Array[int] = []
	var segment_ids: Array[int] = []
	var lod_level: int = 0
	var visible: bool = true


class SimulationChunk extends RefCounted:
	var coord: Vector2i
	var node_ids: Array[int] = []
	var segment_ids: Array[int] = []
	var population: int = 0
	var jobs: int = 0
	var power_demand: float = 0.0
	var power_supply: float = 0.0
	var water_demand: float = 0.0
	var water_supply: float = 0.0
	var dirty: bool = true


class NetworkChunk extends RefCounted:
	var coord: Vector2i
	var node_ids: Array[int] = []
	var segment_ids: Array[int] = []
	var intersection_node_ids: Array[int] = []
	var dirty: bool = true


var render_chunk_size: float
var simulation_chunk_size: float
var network_chunk_size: float

var render_chunks: Dictionary = {}
var simulation_chunks: Dictionary = {}
var network_chunks: Dictionary = {}


func _init(render_size: float = 32.0, simulation_size: float = 64.0, network_size: float = 24.0) -> void:
	render_chunk_size = render_size
	simulation_chunk_size = simulation_size
	network_chunk_size = network_size


func rebuild_from_network(road_network: RoadNetworkData) -> void:
	render_chunks.clear()
	simulation_chunks.clear()
	network_chunks.clear()

	if road_network == null:
		return

	_index_nodes(road_network)
	_index_segments(road_network)
	_finalize_network_chunks(road_network)


func get_render_chunk_list() -> Array[RenderChunk]:
	var chunks: Array[RenderChunk] = []
	for chunk: RenderChunk in render_chunks.values():
		chunks.append(chunk)
	return chunks


func get_render_chunk(coord: Vector2i) -> RenderChunk:
	return render_chunks.get(coord, null)


func get_simulation_chunk_list() -> Array[SimulationChunk]:
	var chunks: Array[SimulationChunk] = []
	for chunk: SimulationChunk in simulation_chunks.values():
		chunks.append(chunk)
	return chunks


func get_network_chunk_list() -> Array[NetworkChunk]:
	var chunks: Array[NetworkChunk] = []
	for chunk: NetworkChunk in network_chunks.values():
		chunks.append(chunk)
	return chunks


func _index_nodes(road_network: RoadNetworkData) -> void:
	for node: RoadNetworkData.RoadNode in road_network.nodes:
		_get_or_create_render_chunk(road_network.get_chunk_coord(node.position, render_chunk_size)).node_ids.append(node.id)
		_get_or_create_simulation_chunk(road_network.get_chunk_coord(node.position, simulation_chunk_size)).node_ids.append(node.id)

		var network_chunk := _get_or_create_network_chunk(road_network.get_chunk_coord(node.position, network_chunk_size))
		network_chunk.node_ids.append(node.id)
		if node.connected_segment_ids.size() > 2:
			network_chunk.intersection_node_ids.append(node.id)


func _index_segments(road_network: RoadNetworkData) -> void:
	for segment: RoadNetworkData.RoadSegment in road_network.segments:
		for coord in road_network.get_segment_chunk_coords(segment, render_chunk_size):
			_get_or_create_render_chunk(coord).segment_ids.append(segment.id)

		for coord in road_network.get_segment_chunk_coords(segment, simulation_chunk_size):
			var simulation_chunk := _get_or_create_simulation_chunk(coord)
			simulation_chunk.segment_ids.append(segment.id)
			_accumulate_segment_simulation(simulation_chunk, segment)

		for coord in road_network.get_segment_chunk_coords(segment, network_chunk_size):
			_get_or_create_network_chunk(coord).segment_ids.append(segment.id)


func _finalize_network_chunks(road_network: RoadNetworkData) -> void:
	for chunk: NetworkChunk in network_chunks.values():
		for node_id in chunk.node_ids:
			var node := road_network.get_node(node_id)
			if node != null and node.connected_segment_ids.size() > 2 and not chunk.intersection_node_ids.has(node_id):
				chunk.intersection_node_ids.append(node_id)


func _accumulate_segment_simulation(chunk: SimulationChunk, segment: RoadNetworkData.RoadSegment) -> void:
	var profile := segment.road_profile
	if profile == null:
		return

	var lane_count: int = max(profile.get_total_lane_count(), 1)
	chunk.jobs += lane_count
	chunk.population += lane_count * 2
	if profile.carries_power:
		chunk.power_supply += lane_count * 5.0
	if profile.carries_water:
		chunk.water_supply += lane_count * 5.0


func _get_or_create_render_chunk(coord: Vector2i) -> RenderChunk:
	if not render_chunks.has(coord):
		var chunk := RenderChunk.new()
		chunk.coord = coord
		render_chunks[coord] = chunk
	return render_chunks[coord]


func _get_or_create_simulation_chunk(coord: Vector2i) -> SimulationChunk:
	if not simulation_chunks.has(coord):
		var chunk := SimulationChunk.new()
		chunk.coord = coord
		simulation_chunks[coord] = chunk
	return simulation_chunks[coord]


func _get_or_create_network_chunk(coord: Vector2i) -> NetworkChunk:
	if not network_chunks.has(coord):
		var chunk := NetworkChunk.new()
		chunk.coord = coord
		network_chunks[coord] = chunk
	return network_chunks[coord]
