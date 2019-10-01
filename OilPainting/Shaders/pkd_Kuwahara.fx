/*
	Kuwahara convolutional shader for GShade - v1.0
	by Packetdancer

	With the 'rotation' option unchecked, this performs a fairly normal Kuwahara 
	filter. With the rotation option checked, however, the dominant angle of 
	each pixel will be determined using Sobel Edge Detection, and then the Kuwahara
	kernel for that pixel will be rotated to match that angle. This creates a
	slightly smoother effect, where things look a little more like brushstrokes.

	It's worth noting that if the LOD and the Radius values get too far out of
	alignment, the results get... interesting.

	This is primarily intended to be used for creating 'painterly' effects for 
	various presets, but no doubt others can find other creative ways to use it.

	CHANGELOG:

	v1.0 - 2019/09/30
	* Initial release

*/


#include "ReShade.fxh"

static const float2 PIXEL_SIZE 		= float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

#define TEXEL_SIZE_FOR_LOD(x) PIXEL_SIZE.xy * pow(2.0,x);

static const float3 CFG_KUWAHARA_LUMINANCE = float3(0.3, 0.6, 0.1);

uniform float CFG_KUWAHARA_LOD <
	ui_type = "slider";
	ui_label = "Texel LOD";
	ui_tooltip = "How large of a texel should we use when performing the Kuwahara convolution. Smaller numbers are more detail, larger are less.";
	ui_min = -1.0; ui_max = 2.5; ui_step = 0.01;
> = -0.4;

uniform int2 CFG_KUWAHARA_RADIUS <
	ui_type = "slider";
	ui_label = "Radius";
	ui_tooltip = "X and Y radius of the kernels to use.";
	ui_min = 2; ui_max = 10; ui_step = 1;
> = int2(5, 5);

uniform bool CFG_KUWAHARA_ROTATION <
	ui_label = "Enable Rotation";
	ui_tooltip = "If true, the Kuwahara kernel calculation will be rotated to the dominant angle. In theory, this should produce a smoother effect.";
> = true;

float PixelAngle(float2 texcoord : TEXCOORD0)
{
    float sobelX[9] = {1, 2, 1, 0, 0, 0, -1, -2, -1}; 
    float sobelY[9] = {-1, 0, 1, -2, 0, 2, -1, 0, 1};
	int sobelIndex = 0;

	float2 gradient = float2(0, 0);

	float2 texelSize = TEXEL_SIZE_FOR_LOD(CFG_KUWAHARA_LOD);

	for (int x = -1; x <= 1; x++)
	{
		for (int y = -1; y <= 1; y++)
		{
			float2 offset = float2(x, y) * texelSize;
			float3 color = tex2D(ReShade::BackBuffer, texcoord + offset).rgb;
			float value = dot(color, color);

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

	float2 texelSize = TEXEL_SIZE_FOR_LOD(CFG_KUWAHARA_LOD);

	for (int x = kernelRange.x; x <= kernelRange.y; x++) 
	{
		for (int y = kernelRange.z; y <= kernelRange.w; y++)
		{
			float2 offset = 0.0;

			if (CFG_KUWAHARA_ROTATION) 
			{
				offset = mul(float2(x, y) * texelSize, rotation);
			}
			else 
			{
				offset = float2(x, y) * texelSize;
			}

			float3 color = tex2D(ReShade::BackBuffer, origin + offset).rgb;

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

	float4 range;

	// Calculate e
	range = float4(-CFG_KUWAHARA_RADIUS[0], 0, -CFG_KUWAHARA_RADIUS[1], 0);
	meanVariance[0] = KernelMeanAndVariance(texcoord, range, rotation);

	range = float4(0, CFG_KUWAHARA_RADIUS[0], -CFG_KUWAHARA_RADIUS[1], 0);
	meanVariance[1] = KernelMeanAndVariance(texcoord, range, rotation);

	range = float4(-CFG_KUWAHARA_RADIUS[0], 0, 0, CFG_KUWAHARA_RADIUS[1]);
	meanVariance[2] = KernelMeanAndVariance(texcoord, range, rotation);

	range = float4(0, CFG_KUWAHARA_RADIUS[0], 0, CFG_KUWAHARA_RADIUS[1]);
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