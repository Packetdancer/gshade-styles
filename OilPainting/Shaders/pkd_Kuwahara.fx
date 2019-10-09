/*
	Kuwahara convolutional shader for GShade - v1.0
	by Packetdancer

	With the 'rotation' option unchecked, this performs a fairly normal Kuwahara 
	filter. With the rotation option checked, however, the dominant angle of 
	each pixel will be determined using Sobel Edge Detection, and then the Kuwahara
	kernel for that pixel will be rotated to match that angle. This creates a
	slightly smoother effect, where things look a little more like brushstrokes.

	The depth-aware part will increase the radius based on distance from the camera;
	it's not complex, but the effect is that the background will be 'painted' with
	less detail than the foreground.

	I had an 'adaptive' mode that alternatively tried to figure out the ideal 
	radius for a given kernel, but it did not play well with others (and was 
	kind of computationally expensive), so I yanked that functionality.

	It's worth noting that if the LOD and the Radius values get too far out of
	alignment, the results get... interesting.

	This is primarily intended to be used for creating 'painterly' effects for 
	various presets, but no doubt others can find other creative ways to use it.

	CHANGELOG:

	v1.1 - 2019/10/01
	* Add depth-aware Kuwahara variant, with sky masking (to preserve stars).
	* Improve rotation logic.

	v1.0 - 2019/09/30
	* Initial release, with baseline and rotated Kuwahara variants.

*/


#include "ReShade.fxh"

static const float2 PIXEL_SIZE 		= float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

#define TEXEL_SIZE_FOR_LOD(lod) PIXEL_SIZE.xy * pow(2.0, lod);

static const float3 CFG_KUWAHARA_LUMINANCE = float3(0.3, 0.6, 0.1);

uniform float2 CFG_KUWAHARA_RADIUS <
	ui_type = "slider";
	ui_label = "Radius";
	ui_tooltip = "X and Y radius of the kernels to use.";
	ui_min = 1.1; ui_max = 6; ui_step = 0.1;
> = float2(4, 4);

uniform float CFG_KUWAHARA_LOD <
 	ui_type = "slider";
 	ui_category = "Experimental";
 	ui_label = "Texel LOD";
	ui_tooltip = "How large of a texel offset should we use when performing the Kuwahara convolution. Smaller numbers are more detail, larger are less.";
	ui_min = 0.25; ui_max = 2.0; ui_step = 0.01;
> = 0.2;

uniform bool CFG_KUWAHARA_ROTATION <
	ui_category = "Experimental";
	ui_label = "Enable Rotation";
	ui_tooltip = "If true, the Kuwahara kernel calculation will be rotated to the dominant angle. In theory, this should produce a slightly more painting-like effect by eliminating the 'boxy' effect that Kuwahara filters sometimes produce.";
> = true;

uniform bool CFG_KUWAHARA_DEPTHAWARE <
	ui_category = "Experimental";
	ui_label = "Enable Depth Awareness";
	ui_tooltip = "Adjust the Kuwahara radius based on depth, which will ensure the foreground elements have more detail than background.";
> = false;

uniform bool CFG_KUWAHARA_DEPTHAWARE_EXCLUDESKY <
	ui_category = "Experimental";
	ui_label = "Depth-Awareness Excludes Sky";
	ui_tooltip = "Exclude the sky from the depth-aware portion of the Kuwahara filter. Useful for retaining stars in a night sky.";
> = false;

uniform int CFG_KUWAHARA_DEPTHAWARE_SKYBLEND_STYLE <
	ui_type = "combo";
	ui_category = "Experimental";
	ui_label = "Sky Blend Style";
	ui_tooltip = "Once we restore the sky, how should we blend it?";
	ui_items = "Adaptive\0Favor Dark\0Favor Light\0Manual Blend";
> = 0;

uniform float CFG_KUWAHARA_DEPTHAWARE_SKYBLEND_STRENGTH <
	ui_type = "slider";
	ui_category = "Experimental";
	ui_label = "Sky Blend Manual Strength";
	ui_tooltip = "If the blend style is 'Manual Blend', how strong should the blend be? (0 is the painted foreground, 1.0 is the preserved sky.)";
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = 0.5;

uniform float2 CFG_KUWAHARA_DEPTHAWARE_CURVE <
	ui_type = "slider";
	ui_category = "Experimental";
	ui_label = "Depth-aware Curve";
	ui_tooltip = "Start/end values for where the foreground will transition to the background.";
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = float2(0.12, 0.55);

uniform float2 CFG_KUWAHARA_DEPTHAWARE_MINRADIUS <
	ui_type = "slider";
	ui_category = "Experimental";
	ui_label = "Minimum Radius";
	ui_tooltip = "The smallest radius, to use for the foreground elements.";
	ui_min = 1.2; ui_max = 5.9; ui_step = 0.1;
> = float2(2, 2);

texture texSky { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
sampler sampSky { Texture = texSky; };

float PixelAngle(float2 texcoord : TEXCOORD0)
{
    float sobelX[9] = {-1, -2, -1, 0, 0, 0, 1, 2, 1}; 
    float sobelY[9] = {-1, 0, 1, -2, 0, 2, -1, 0, 1};
	int sobelIndex = 0;

	float2 gradient = float2(0, 0);

	float2 texelSize = TEXEL_SIZE_FOR_LOD(CFG_KUWAHARA_LOD);

	for (int x = -1; x <= 1; x++)
	{
		for (int y = -1; y <= 1; y++)
		{
			float2 offset = float2(x, y) * (texelSize * 0.5);
			float3 color = tex2Dlod(ReShade::BackBuffer, float4((texcoord + offset).xy, 0, 0)).rgb;
			float value = dot(color, float3(0.3, 0.59, 0.11));

			gradient[0] += value * sobelX[sobelIndex];
			gradient[1] += value * sobelY[sobelIndex];
			sobelIndex++;
		}
	}

	return atan(gradient[1] / gradient[0]);
}

float4 KernelMeanAndVariance(float2 origin : TEXCOORD0, float4 kernelRange, 
	float2x2 rotation)
{
	float3 mean = float3(0, 0, 0);
	float3 variance = float3(0, 0, 0);
	int samples = 0;

	float4 range = kernelRange;

	float2 texelSize = TEXEL_SIZE_FOR_LOD(CFG_KUWAHARA_LOD);

	for (int u = range.x; u <= range.y; u++) 
	{
		for (int v = kernelRange.z; (v <= kernelRange.w); v++)
		{
			float2 offset = 0.0;

			if (CFG_KUWAHARA_ROTATION) 
			{
				offset = mul(float2(u, v) * texelSize, rotation);
			}
			else 
			{
				offset = float2(u, v) * texelSize;
			}

			float3 color = tex2Dlod(ReShade::BackBuffer, float4((origin + offset).xy, 0, 0)).rgb;

			mean += color; variance += color * color;
			samples++;
		}
	}

	mean /= samples;
	variance = variance / samples - mean * mean;
	return float4(mean, variance.r + variance.g + variance.b);
}

float3 Kuwahara(float2 texcoord, float2 radius, float2x2 rotation)
{
	float4 range;
	float4 meanVariance[4];

	range = float4(-radius[0], 0, -radius[1], 0);		
	meanVariance[0] = KernelMeanAndVariance(texcoord, range, rotation);

	range = float4(0, radius[0], -radius[1], 0);
	meanVariance[1] = KernelMeanAndVariance(texcoord, range, rotation);

	range = float4(-radius[0], 0, 0, radius[1]);
	meanVariance[2] = KernelMeanAndVariance(texcoord, range, rotation);

	range = float4(0, radius[0], 0, radius[1]);
	meanVariance[3] = KernelMeanAndVariance(texcoord, range, rotation);

	float3 result = meanVariance[0].rgb;
	float currentVariance = meanVariance[0].a;

	// Find the color with the lowest variance.
	for (int i = 1; i < 4; i++)
	{
		if (meanVariance[i].a < currentVariance)
		{
			result = meanVariance[i].rgb;
			currentVariance = meanVariance[i].a;
		}
	}

	return result;
	
}

float4 PS_SkyKeep(float4 pos : SV_Position, float2 texcoord : TEXCOORD0) : SV_Target
{
	if (!CFG_KUWAHARA_DEPTHAWARE_EXCLUDESKY)
	{
		return float4(0, 0, 0, 0);
	}

	float angle = 0.0;
	float2x2 rotation = float2x2(0.0, 0.0, 0.0, 0.0);

	if (CFG_KUWAHARA_ROTATION)
	{
		angle = PixelAngle(texcoord);
		rotation = float2x2(cos(angle), -sin(angle), sin(angle), cos(angle));
	}

	float depth = ReShade::GetLinearizedDepth(texcoord);
	float4 color = tex2D(ReShade::BackBuffer, texcoord);

	if (depth <= 0.99)
	{
		return float4(0, 0, 0, 0);
	}

	float3 result = Kuwahara(texcoord, CFG_KUWAHARA_DEPTHAWARE_MINRADIUS, rotation).rgb;

	return float4(result, 1.0);
}

float3 PS_SkyRestore(float4 pos : SV_Position, float2 texcoord : TEXCOORD0) : SV_Target
{
	float4 bb = tex2D(ReShade::BackBuffer, texcoord);
	if (!CFG_KUWAHARA_DEPTHAWARE_EXCLUDESKY)
	{
		return bb.rgb;
	}

	float4 sky = tex2D(sampSky, texcoord);
	if (sky.a == 0)
	{
		return bb.rgb;
	}

	// Calculate luminance per ITU BT.601
	float3 lumITU = float3(0.299, 0.587, 0.114);

	float lumBB = (bb.r * lumITU.r) + (bb.g * lumITU.g) + (bb.b * lumITU.b); 
	float lumSky = (sky.r * lumITU.r) + (sky.g * lumITU.g) + (sky.b * lumITU.b); 

	if (lumBB >= lumSky) {
		return bb.rgb;
	}
	else {
		float alpha;

		if (CFG_KUWAHARA_DEPTHAWARE_SKYBLEND_STYLE == 0)
		{
			// We want to slightly bias in favor of light in order to catch stars
			float magBB = (lumBB < 0.5) ? abs(lumBB - 1.0) : lumBB + 0.3;
			float magSky = (lumSky < 0.5) ? abs(lumSky - 1.0) : lumSky + 0.3; 

			alpha = (magBB > magSky) ? 0.02 : 0.98; 
		}
		else if (CFG_KUWAHARA_DEPTHAWARE_SKYBLEND_STYLE == 1)
		{
			alpha = (lumBB < lumSky) ? lumBB : lumSky;
		}
		else if (CFG_KUWAHARA_DEPTHAWARE_SKYBLEND_STYLE == 2)
		{
			alpha = (lumBB > lumSky) ? lumBB : lumSky;
		}
		else
		{
			alpha = CFG_KUWAHARA_DEPTHAWARE_SKYBLEND_STRENGTH;
		}

		return lerp(bb.rgb, sky.rgb, alpha);
	}
}

float3 PS_Kuwahara(float4 pos : SV_Position, float2 texcoord : TEXCOORD0) : SV_Target
{
	float4 meanVariance[4];

	float angle = 0.0;
	float2x2 rotation = float2x2(0.0, 0.0, 0.0, 0.0);

	if (CFG_KUWAHARA_ROTATION)
	{
		angle = PixelAngle(texcoord);
		rotation = float2x2(cos(angle), -sin(angle), sin(angle), cos(angle));
	}

	float2 radius = CFG_KUWAHARA_RADIUS;

	if (CFG_KUWAHARA_DEPTHAWARE) 
	{
		float2 delta = CFG_KUWAHARA_RADIUS - CFG_KUWAHARA_DEPTHAWARE_MINRADIUS;

		float depth = ReShade::GetLinearizedDepth(texcoord);

		float percent = smoothstep(CFG_KUWAHARA_DEPTHAWARE_CURVE[0], 
		CFG_KUWAHARA_DEPTHAWARE_CURVE[1], depth);

		radius = CFG_KUWAHARA_DEPTHAWARE_MINRADIUS + (delta * percent);
	}

	return Kuwahara(texcoord, radius, rotation).rgb;
}

technique pkd_Kuwahara
{
	pass SkyStore
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_SkyKeep;
		RenderTarget = texSky;
	}

	pass Filter
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Kuwahara;
	}

	pass SkyRestore
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_SkyRestore;
	}
}