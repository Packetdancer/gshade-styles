# Sketchbook Style

![Sketchbook Style Example](https://github.com/packetdancer/gshade-styles/raw/master/OilPainting/example.png)

## Instructions for Installation

Go to your FFXIV directory, and into the `game` subdirectory.

* Copy the contents of the `Presets` directory in this archive into the `reshade-presets/GShade` directory

* Copy the contents of the Shaders directory in this archive into the `reshade-shaders/Shaders` directory

* Have fun with the preset!


## Instructions on Use

The main part of this preset which will change the 'feel' of it is the `pkd_Kuwahara` technique, which creates the 'painting' effect itself.

There are effectively two ways to adjust the detail, which might get confusing, but they adjust the detail in different ways; the vastly simplified form is that the **Radius** values determine how wide of a paintbrush to use, while the **Texel LOD** determines how precise the brush strokes are. (This isn't actually mathematically accurate, but it works well enough as an analogy.)

Normally the Kuwahara filter is applied in squares, which can lead to an oddly boxy look in some places. If you check the **Enable Rotation** box, the shader will attempt to determine the dominant angle for each pixel and rotate the Kuwahara kernel for the pixel onto that angle. The upshot of which is that you will get 'brush strokes' that feel marginally more directional.

## Credits and Attribution

While `pkd_Kuwahara.fx` is my own work, pieces of it were inspired by the Nvidia 