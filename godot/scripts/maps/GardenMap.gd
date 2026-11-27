extends MapBase

## Backyard Garden.

func build() -> void:
	add_child(GardenWorld.build())
