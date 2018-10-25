Shader "Hidden/Lightweight Render Pipeline/Blit"
{
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "LightweightPipeline"}
        LOD 100

        Pass
        {
            Name "Blit"
            ZTest Always ZWrite Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "Packages/com.unity.render-pipelines.lightweight/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                half4 positionCS       : SV_POSITION;
                half2 uv        : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            UNITY_DECLARE_SCREENSPACE_TEXTURE(_BlitTex);

            Varyings Vertex(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            half4 Fragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
				return half4(UNITY_SAMPLE_SCREENSPACE_TEXTURE(_BlitTex, input.uv));
            }
            ENDHLSL
        }
    }
}
