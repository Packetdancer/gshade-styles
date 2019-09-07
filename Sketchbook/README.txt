Packetdancer's Sketchbook Preset for GShade
===========================================

INSTRUCTIONS ON INSTALLATION

Go to your FFXIV directory, and into the 'game' subdirectory.

* Copy the contents of the Presets directory in this archive into the reshade-presets/GShade directory

* Copy the contents of the Shaders directory in this archive into the reshade-shaders/Shaders directory

* Copy the contents of the Textures directory in this archive into the reshade-shaders/Textures directory

* Have fun with the preset!


INSTRUCTIONS ON USE

Because of the way this filter works, adjusting lighting can be a bit  tricky. The main thing to keep in mind is that color matters almost more than intensity here. 

* Green light is dominant; the more green light something has, the less shading it will have at all. Green light, effectively, is your eraser to show the paper underneath. 

* Red light controls the detail *within* the shading; if you need more detail within a big expanse of shading, try tweaking the red light. 

* Blue light does very little, but will adjust shading slightly.

If you find that lighting alone isn't enough, you will want to hit up the LevelsPlus settings and adjust the red and green gamma levels to change your baseline 'exposure'. You will also find that if you need to bring more of the background into the shot, you'll want to adjust the RetroFog distance that's used to fade out objects.

It's worth noting that the shading 'style' -- for lack of a better term -- will change as well if you change the effect in /gpose; the Bright settings
in particular are very useful to try different looks/feels out for a scene.

Really, so far I've found lighting a shot in this to be more an art than a science. There's no one setting that will work for everything!


TWEAKING THE TEXTURES

The textures useful for tweaking are SketchPattern.png (the image used to overlay the actual pencil strokes), SketchPage.png (the image stuck atop the sketch image), and SketchMask.png (the mask used to show the sketch through the page). If you use the optional SketchPaperOverlay technique, you'll also
want SketchOverlay.png -- changing these can change the look of your picture rather dramatically.

I admit I haven't found another good pencil stroke texture that I like yet;
when I do, I'll add additional SketchPattern textures and update the techniques so that it's possible to switch between various options.


CREDITS AND ATTRIBUTION

"SketchLevel<whatever>.fx" shaders are just the standard GShade Level shader, duplicated and modified so they don't conflict with other people's customized Layer setups. The actual shaders remain the work of their original authors.

"SketchMask.fx" is the standard ReShade UIMask.fx, modified to be specific to this particular preset (in order to avoid conflicts).

Pencil sketch texture started life as a tile by Werner Hörer licensed under Creative Commons Share-Alike; anyone is free to use the modified version included herein.
Original: https://www.flickr.com/photos/63231715@N00/404666644

SketchMask image is my own work; use it if you want, though I see very few uses for it outside of this!

Optional 'paper' texture from a free pack by Arno Kathollnig.
Original: https://dribbble.com/shots/1408488-12-Paper-Textures
