/*
	Kuwahara convolutional shader for GShade - v1.0
	by Packetdancer

	With the 'rotation' option unchecked, this performs a fairly normal Kuwahara 
	filter. With the rotation option checked, however, the dominant angle of 
	each pixel will be determined using Sobel Edge Detection, and then the Kuwahara
	kernel for that pixel will be rotated to match that angle. This creates a
	slightly smoother effect, where things look a little more like brushstrokes.

	The 'adaptive' functionality will run the filter for each quadrant repeatedly,
	for sizes between that passed in and the minimum adaptive size defined in 
	configuration. The result with the smallest variance will be taken. This
	will create a much sharper result, especially when combined with rotation,
	as it should honor lines. This is less useful for the painting, really,
	and more for if this shader is used as a denoise pass.

	It's worth noting that if the LOD and the Radius values get too far out of
	alignment, the results get... interesting.

	This is primarily intended to be used for creating 'painterly' effects for 
	various presets, but no doubt others can find other creative ways to use it.

	CHANGELOG:

	v1.1 - 2019/10/01
	* Add depth-aware Kuwahara variant.
	* Improve rotation logic.

	v1.0 - 2019/09/30
	* Initial release, with baseline and rotated Kuwahara variants.

*/


#include "ReShade.fxh"

static const float2 PIXEL_SIZE 		= float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

#define TEXEL_SIZE_FOR_LOD(lod) PIXEL_SIZE.xy * pow(2.0, lod);

static const float3 CFG_KUWAHARA_LUMINANCE = float3(0.3, 0.6, 0.1);

uniform int2 CFG_KUWAHARA_RADIUS <
	ui_type = "slider";
	ui_label = "Radius";
	ui_tooltip = "X and Y radius of the kernels to use.";
	ui_min = 1; ui_max = 6; ui_step = 1;
> = int2(4, 4);

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
	ui_tooltip = "If true, the Kuwahara kernel calculation will be rotated to the dominant angle. In theory, this should produce a slightly more painting-like effect.";
> = true;

uniform bool CFG_KUWAHARA_DEPTHAWARE <
	ui_category = "Experimental";
	ui_label = "Enable Depth Awareness";
	ui_tooltip = "Adjust the Kuwahara radius based on depth, which will ensure the foreground elements have more detail than background.";
> = false;

uniform float2 CFG_KUWAHARA_DEPTHAWARE_CURVE <
	ui_type = "slider";
	ui_category = "Experimental";
	ui_label = "Curve Ends";
	ui_tooltip = "Start/end values for where the foreground will transition to the background.";
	ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
> = float2(0.12, 0.55);

uniform int2 CFG_KUWAHARA_DEPTHAWARE_MINRADIUS <
	ui_type = "slider";
	ui_category = "Experimental";
	ui_label = "Minimum Radius";
	ui_tooltip = "The smallest radius, to use for the foreground elements.";
	ui_min = 1; ui_max = 5; ui_step = 1;
> = int2(2, 2);

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

	float2 radius = float2(CFG_KUWAHARA_RADIUS);

	if (CFG_KUWAHARA_DEPTHAWARE) 
	{
		float2 delta = float2(CFG_KUWAHARA_RADIUS - CFG_KUWAHARA_DEPTHAWARE_MINRADIUS);

		float depth = ReShade::GetLinearizedDepth(texcoord).x;

		float percent = smoothstep(CFG_KUWAHARA_DEPTHAWARE_CURVE[0], 
			CFG_KUWAHARA_DEPTHAWARE_CURVE[1], depth);

		radius = float2(CFG_KUWAHARA_DEPTHAWARE_MINRADIUS) + (delta * percent);
	}

	float4 range;

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

technique pkd_Kuwahara
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Kuwahara;
	}
}