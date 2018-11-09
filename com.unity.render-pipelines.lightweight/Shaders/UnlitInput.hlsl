#ifndef LIGHTWEIGHT_UNLIT_INPUT_INCLUDED
#define LIGHTWEIGHT_UNLIT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/SurfaceInput.hlsl"

CBUFFER_START(UnityPerMaterial)
float4 _MainTex_ST;
float4 _Color;
float _Cutoff;
float _Glossiness;
float _Metallic;
CBUFFER_END

#endif
