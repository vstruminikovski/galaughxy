# Credits

## DOGWALK (Blender Studio)
Several systems are adapted from the source of DOGWALK by Blender Studio, licensed under
Creative Commons Attribution 4.0 (https://creativecommons.org/licenses/by/4.0/):

(CC) Blender Foundation | studio.blender.org

These were rewritten for this project, not copied:
- reaction bubbles over characters (after DOGWALK's emote bubbles)
- wind sway on foliage (after `wind.gdshaderinc`)
- dissolving geometry that sits between the camera and the subject (after the dithered depth blend)
- props that wobble when a character bumps into them (after the bushes)
- the follow / two-shot camera that frames a pair and pushes in when idle (after the game camera)
- falling snow and snow cover (after the snow FX)

No DOGWALK art, textures, models, sounds or logos are included. Source mirror used for reference:
https://github.com/nikitalita/DOGWALK

## 0 A.D. (Wildfire Games)
Buildings in the history maps (Roman Forum, Nile of the Pharaohs) are converted from 0 A.D. art,
Copyright (C) Wildfire Games, https://www.wildfiregames.com/, licensed CC-BY-SA 3.0
(http://creativecommons.org/licenses/by-sa/3.0/). The converted pieces stay CC-BY-SA 3.0. See
godot/assets/history/LICENSE.md, including the credit line to use in videos.

## Reviewed, not used
- polyworld (MIT, Nim engine) was read for ideas only. Its deterministic replay matches what the
  Director already does, and its physics recording was the model for StudioPhysics.
- Kiln (MIT) was not run. Our Blender kit already generates assets as code with verification renders.
- CC0Tree (CC0) has mostly modern props. The physics objects were built in our own kit instead,
  so they match the style.

## Fonts
Poppins ExtraBold, SIL Open Font License 1.1 (`godot/assets/fonts/OFL-Poppins.txt`).
