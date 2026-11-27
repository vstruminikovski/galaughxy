extends MapBase

## Pond Life: uneven terrain, so it reports the pond's height field as ground.

var pond: PondWorld

func build() -> void:
	pond = PondWorld.new()
	add_child(pond.build())

func ground(x: float, z: float) -> float:
	return pond.ground(x, z)
