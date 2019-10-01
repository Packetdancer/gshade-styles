/* Perlin Noise Line Integral Convolution shader v1.0
 * Packetdancer - 2019
 *
 * This work is licensed under the MIT License, and is free to modify or 
 * use in your own projects, including commercial ones.
 *
 * I'm genuinely not certain there's a reason anyone would use this particular
 * pairing of functions outside of my own Watercolor style, but if you have a
 * use for it, go nuts.
 */

uniform int flowLength <
	ui_label = "Flow Length";
	ui_tooltip = "How many iterations of convolution should we go through?";
	ui_category = "Convolution";
> = 10;




float4 LIC(float4 vpos : SV_Position, float2 texCoord : TexCoord) : SV_Target
{
	float3 col = tex2D(noise_Tex, texCoord);
	int w = 0;
	
	float2 v = (tex2D(vectorField_Tex, texCoord).xy - 0.5) * 2;
	v.x *= vectorField_TexelSize.x;
	v.y *= vectorField_TexelSize.y;
	
	float2 st0 = texCoord;
	for(int i = 0; i < flowLength; i++) {
		st0 += v;
		float3 n = tex2D(_NoiseTex, st0).rgb;
		col += n;
		w++;
	}
	
	float2 st1 = IN.uv;
	for(int i = 0; i < flowLength; i++) {
		st1 -= v;
		float3 n = tex2D(_NoiseTex, st1).rgb;
		col += n;
		w++;
	}

	col /= w;

	return float4(col, 1);
}