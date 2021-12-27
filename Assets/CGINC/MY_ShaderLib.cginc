// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

#include "UnityCG.cginc"
#include "Autolight.cginc"
#include "Shaders/CustomTessellation.cginc"
#define BLADE_SEGMENTS 3
float _BendRotationRandom;
float _BladeHeight;
float _BladeHeightRandom;	
float _BladeWidth;
float _BladeWidthRandom;

sampler2D _WindDistortionMap;
float4 _WindDistortionMap_ST;
float2 _WindFrequency;
float _WindStrength;

float _BladeForward;
float _BladeCurve;

float _Strength;
float _Radius;

uniform float3 _PositionMoving;

float rand(float3 co)
{
	return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
};

float3x3 AngleAxis3x3(float angle, float3 axis)
{
	float c, s;
	sincos(angle, s, c);

	float t = 1 - c;
	float x = axis.x;
	float y = axis.y;
	float z = axis.z;

	return float3x3(
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c
		);
};


struct geometryOutput{
	float4 pos : SV_POSITION;
	float2 uv : TEXCOORD0;
	unityShadowCoord4 _ShadowCoord : TEXCOORD1;
	float3 normal : NORMAL;
};


geometryOutput VertexOutput (float3 pos, float2 uv, float3 normal) {
	geometryOutput o;
	o.pos = UnityObjectToClipPos(pos);
	o.uv = uv;
	o._ShadowCoord = ComputeScreenPos(o.pos);
	o.normal = UnityObjectToWorldNormal(normal);
	#if UNITY_PASS_SHADOWCASTER
	// Applying the bias prevents artifacts from appearing on the surface.
		o.pos = UnityApplyLinearShadowBias(o.pos);
	#endif
	return o;
};

geometryOutput GenerateGrassVertex(float3 vertexPosition, float width, float height, float forward, float2 uv, float3x3 transformMatrix)
{
	float3 tangentPoint = float3(width, forward, height);
	float3 tangentNormal = normalize(float3(0, -1, forward));
	float3 localNormal = mul(transformMatrix, tangentNormal);
	float3 localPosition = vertexPosition + mul(transformMatrix, tangentPoint);
	return VertexOutput(localPosition, uv, localNormal);
};

[maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
void geo(triangle vertexOutput IN[3] : SV_POSITION, inout TriangleStream<geometryOutput> triStream){

	float3 pos = IN[0].vertex;
	float3 worldPos = mul(unity_ObjectToWorld, pos);

	float3 vNormal = IN[0].normal;
	float4 vTangent = IN[0].tangent;
	float3 vBinormal = cross(vNormal, vTangent) * vTangent.w;

	float3x3 tangentToLocal = float3x3(
		vTangent.x, vBinormal.x, vNormal.x,
		vTangent.y, vBinormal.y, vNormal.y,
		vTangent.z, vBinormal.z, vNormal.z
	);

	float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));
	float3x3 bendRotationMatrix = AngleAxis3x3(rand(pos.zzx) * _BendRotationRandom * UNITY_PI * 0.5, float3(-1, 0, 0));

	float2 uv = pos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
	float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
	float3 wind = normalize(float3(windSample.x, windSample.y, 0));
	float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);

	// Interactivity
    float3 dis = distance(_PositionMoving, worldPos); // distance for radius
    float3 radius = 1 - saturate(dis / _Radius); // in world radius based on objects interaction radius
    float3 sphereDisp = worldPos - _PositionMoving; // position comparison
    sphereDisp *= radius; // position multiplied by radius for falloff
    // increase strength
    sphereDisp = clamp(sphereDisp.xyz * _Strength, -0.8, 0.8);

	float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);
	float3x3 transformationMatrix = mul(mul(mul(tangentToLocal, windRotation), facingRotationMatrix), bendRotationMatrix);

	float height = (rand(pos.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
	float width = (rand(pos.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
	float forward = rand(pos.yyz) * _BladeForward;


	for (int i = 0; i < BLADE_SEGMENTS; i++)
	{
		float t = i / (float)BLADE_SEGMENTS;
		float segmentHeight = height * t;
		float segmentWidth = width * (1 - t);
		float segmentForward = pow(t, _BladeCurve) * forward;

		float3x3 transformMatrix = i == 0 ? transformationMatrixFacing : transformationMatrix;

		// first grass (0) segment does not get displaced by interactivity
        float3 newPos = i == 0 ? pos : pos + float3(sphereDisp.x, sphereDisp.y, sphereDisp.z) * t;

		triStream.Append(GenerateGrassVertex(newPos, segmentWidth, segmentHeight, segmentForward, float2(0, t), transformMatrix));
		triStream.Append(GenerateGrassVertex(newPos, -segmentWidth, segmentHeight, segmentForward, float2(1, t), transformMatrix));
	}
	triStream.Append(GenerateGrassVertex(pos + float3(sphereDisp.x * 1.5, sphereDisp.y, sphereDisp.z * 1.5), 0, height, forward, float2(0.5, 1), transformationMatrix));
}