# 0 A.D. buildings in the history maps

The `Lowpoly_*` meshes inside these files are converted from 0 A.D.:

- `godot/assets/maps/roman_forum/roman_forum.glb`
- `godot/assets/maps/nile_pyramids/nile_pyramids.glb`

To convert them, `tools/zeroad.py` reads the original COLLADA meshes, bakes each face to one flat colour from its texture, snaps the colours to the studio palette, and rescales the result.

Source: 0 A.D. Empires Ascendant art, Copyright (C) Wildfire Games, https://www.wildfiregames.com/
(repository: https://gitea.wildfiregames.com/0ad/0ad).

Licence: Creative Commons Attribution-ShareAlike 3.0, http://creativecommons.org/licenses/by-sa/3.0/

These converted pieces are released under the same CC-BY-SA 3.0 licence. When you publish a video that shows them, credit:

> Buildings: 0 A.D. by Wildfire Games (wildfiregames.com), CC-BY-SA 3.0

Everything else in those map files is part of Galaughxy, not covered by this notice: the ground, water, palms, cypresses, columns, stalls, amphorae and the physics objects, all built by `tools/generate_history_maps.py` and `tools/generate_physics_props.py`.
