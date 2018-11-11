//-------------------------------------------------------------------------------------
// Fill SurfaceData/Builtin data function
//-------------------------------------------------------------------------------------
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/SampleUVMapping.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/BuiltinUtilities.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/MaterialUtilities.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Decal/DecalUtilities.hlsl"
//for void ApplyDecalToSurfaceData(DecalSurfaceData decalSurfaceData, inout SurfaceData surfaceData):
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/StackLit/StackLitDecalData.hlsl"

//-----------------------------------------------------------------------------
// Texture Mapping
//-----------------------------------------------------------------------------

#define TEXCOORD_INDEX_UV0          (0)
#define TEXCOORD_INDEX_UV1          (1)
#define TEXCOORD_INDEX_UV2          (2)
#define TEXCOORD_INDEX_UV3          (3)
#define TEXCOORD_INDEX_PLANAR_XY    (4)
#define TEXCOORD_INDEX_PLANAR_YZ    (5)
#define TEXCOORD_INDEX_PLANAR_ZX    (6)
#define TEXCOORD_INDEX_TRIPLANAR    (7)
#define TEXCOORD_INDEX_COUNT        (TEXCOORD_INDEX_TRIPLANAR) // Triplanar is not consider as having mapping

struct TextureUVMapping
{
    float2 texcoords[TEXCOORD_INDEX_COUNT][2];
#ifdef _MAPPING_TRIPLANAR
    float3 triplanarWeights[2];
#endif

    float3 vertexNormalWS;
    float3 vertexTangentWS[4];
    float3 vertexBitangentWS[4];
};

void InitializeMappingData(FragInputs input, out TextureUVMapping uvMapping)
{
    float2 uvXZ;
    float2 uvXY;
    float2 uvZY;

    // Build the texcoords array.
    uvMapping.texcoords[TEXCOORD_INDEX_UV0][0] = uvMapping.texcoords[TEXCOORD_INDEX_UV0][1] = input.texCoord0.xy;
    uvMapping.texcoords[TEXCOORD_INDEX_UV1][0] = uvMapping.texcoords[TEXCOORD_INDEX_UV1][1] = input.texCoord1.xy;
    uvMapping.texcoords[TEXCOORD_INDEX_UV2][0] = uvMapping.texcoords[TEXCOORD_INDEX_UV2][1] = input.texCoord2.xy;
    uvMapping.texcoords[TEXCOORD_INDEX_UV3][0] = uvMapping.texcoords[TEXCOORD_INDEX_UV3][1] = input.texCoord3.xy;

    // planar/triplanar
    GetTriplanarCoordinate(GetAbsolutePositionWS(input.positionRWS), uvXZ, uvXY, uvZY);
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_XY][0] = uvXY;
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_YZ][0] = uvZY;
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_ZX][0] = uvXZ;

    // If we use local planar mapping, convert to local space
    GetTriplanarCoordinate(TransformWorldToObject(input.positionRWS), uvXZ, uvXY, uvZY);
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_XY][1] = uvXY;
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_YZ][1] = uvZY;
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_ZX][1] = uvXZ;

#ifdef _MAPPING_TRIPLANAR
    float3 vertexNormal = input.worldToTangent[2].xyz;
    uvMapping.triplanarWeights[0] = ComputeTriplanarWeights(vertexNormal);
    // If we use local planar mapping, convert to local space
    vertexNormal = TransformWorldToObjectDir(vertexNormal);
    uvMapping.triplanarWeights[1] = ComputeTriplanarWeights(vertexNormal);
#endif

    // Normal mapping with surface gradient
    float3 vertexNormalWS = input.worldToTangent[2];
    uvMapping.vertexNormalWS = vertexNormalWS;

    uvMapping.vertexTangentWS[0] = input.worldToTangent[0];
    uvMapping.vertexBitangentWS[0] = input.worldToTangent[1];

    float3 dPdx = ddx_fine(input.positionRWS);
    float3 dPdy = ddy_fine(input.positionRWS);

    float3 sigmaX = dPdx - dot(dPdx, vertexNormalWS) * vertexNormalWS;
    float3 sigmaY = dPdy - dot(dPdy, vertexNormalWS) * vertexNormalWS;
    //float flipSign = dot(sigmaY, cross(vertexNormalWS, sigmaX) ) ? -1.0 : 1.0;
    float flipSign = dot(dPdy, cross(vertexNormalWS, dPdx)) < 0.0 ? -1.0 : 1.0; // gives same as the commented out line above

    SurfaceGradientGenBasisTB(vertexNormalWS, sigmaX, sigmaY, flipSign, input.texCoord1.xy, uvMapping.vertexTangentWS[1], uvMapping.vertexBitangentWS[1]);
    SurfaceGradientGenBasisTB(vertexNormalWS, sigmaX, sigmaY, flipSign, input.texCoord2.xy, uvMapping.vertexTangentWS[2], uvMapping.vertexBitangentWS[2]);
    SurfaceGradientGenBasisTB(vertexNormalWS, sigmaX, sigmaY, flipSign, input.texCoord3.xy, uvMapping.vertexTangentWS[3], uvMapping.vertexBitangentWS[3]);
}

float4 SampleTexture2DScaleBias(TEXTURE2D_ARGS(textureName, samplerName), float textureNameUV, float textureNameUVLocal, float4 textureNameST, TextureUVMapping uvMapping)
{
    return SAMPLE_TEXTURE2D(textureName, samplerName, (uvMapping.texcoords[textureNameUV][textureNameUVLocal] * textureNameST.xy + textureNameST.zw));
}

float4 SampleTexture2DScaleBiasLod(TEXTURE2D_ARGS(textureName, samplerName), float textureNameUV, float textureNameUVLocal, float4 textureNameST, float lod, TextureUVMapping uvMapping)
{
    return SAMPLE_TEXTURE2D_LOD(textureName, samplerName, (uvMapping.texcoords[textureNameUV][textureNameUVLocal] * textureNameST.xy + textureNameST.zw), lod);
}

// If we use triplanar on any of the properties, then we enable the triplanar path
float4 SampleTexture2DTriplanarScaleBias(TEXTURE2D_ARGS(textureName, samplerName), float textureNameUV, float textureNameUVLocal, float4 textureNameST, TextureUVMapping uvMapping)
{
#ifdef _MAPPING_TRIPLANAR
    if (textureNameUV == TEXCOORD_INDEX_TRIPLANAR)
    {
        float4 val = float4(0.0, 0.0, 0.0, 0.0);

        if (uvMapping.triplanarWeights[textureNameUVLocal].x > 0.0)
            val += uvMapping.triplanarWeights[textureNameUVLocal].x * SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_YZ, textureNameUVLocal, textureNameST, uvMapping);
        if (uvMapping.triplanarWeights[textureNameUVLocal].y > 0.0)
            val += uvMapping.triplanarWeights[textureNameUVLocal].y * SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_ZX, textureNameUVLocal, textureNameST, uvMapping);
        if (uvMapping.triplanarWeights[textureNameUVLocal].z > 0.0)
            val += uvMapping.triplanarWeights[textureNameUVLocal].z * SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_XY, textureNameUVLocal, textureNameST, uvMapping);

        return val;
    }
    else
    {
#endif // _MAPPING_TRIPLANAR
        return SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), textureNameUV, textureNameUVLocal, textureNameST, uvMapping);
#ifdef _MAPPING_TRIPLANAR
    }
#endif
}

float4 SampleTexture2DTriplanarNormalScaleBias(TEXTURE2D_ARGS(textureName, samplerName), float textureNameUV, float textureNameUVLocal, float4 textureNameST, float textureNameObjSpace, TextureUVMapping uvMapping, float scale)
{
    if (textureNameObjSpace)
    {
        // TODO: obj triplanar (need to do * 2 - 1 before blending)

        // We forbid scale in case of object space as it make no sense
        // Decompress normal ourselve
        float4 packedNormal = SampleTexture2DTriplanarScaleBias(TEXTURE2D_PARAM(textureName, samplerName), textureNameUV, textureNameUVLocal, textureNameST, uvMapping);
        float3 normalOS = packedNormal.xyz * 2.0 - 1.0;
        float normalVariance = packedNormal.w; // If we used a object space normal map that store average normal, the formap is RGB (normal xyz) and A (a measure of normal dispersion: ie variance or the average normal's length)
        // no need to renormalize normalOS for SurfaceGradientFromPerturbedNormal
        return float4(SurfaceGradientFromPerturbedNormal(uvMapping.vertexNormalWS, TransformObjectToWorldDir(normalOS)), normalVariance);
    }
    else
    {
#ifdef _MAPPING_TRIPLANAR
        if (textureNameUV == TEXCOORD_INDEX_TRIPLANAR)
        {
            float2 derivXplane;
            float2 derivYPlane;
            float2 derivZPlane;
            derivXplane = derivYPlane = derivZPlane = float2(0.0, 0.0);
            float normalVariance = 0.0;

            if (uvMapping.triplanarWeights[textureNameUVLocal].x > 0.0)
            {
                float4 packedNormal = SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_YZ, textureNameUVLocal, textureNameST, uvMapping);
                normalVariance += uvMapping.triplanarWeights[textureNameUVLocal].x * packedNormal.z;
                derivXplane = uvMapping.triplanarWeights[textureNameUVLocal].x * UnpackDerivativeNormalRGorAG(packedNormal, scale);
            }
            if (uvMapping.triplanarWeights[textureNameUVLocal].y > 0.0)
            {
                float4 packedNormal = SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_ZX, textureNameUVLocal, textureNameST, uvMapping);
                normalVariance += uvMapping.triplanarWeights[textureNameUVLocal].y * packedNormal.z;
                derivYPlane = uvMapping.triplanarWeights[textureNameUVLocal].y * UnpackDerivativeNormalRGorAG(packedNormal, scale);
            }
            if (uvMapping.triplanarWeights[textureNameUVLocal].z > 0.0)
            {
                float4 packedNormal = SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_XY, textureNameUVLocal, textureNameST, uvMapping);
                normalVariance += uvMapping.triplanarWeights[textureNameUVLocal].z * packedNormal.z;
                derivZPlane = uvMapping.triplanarWeights[textureNameUVLocal].z * UnpackDerivativeNormalRGorAG(packedNormal, scale);
            }

            // Assume derivXplane, derivYPlane and derivZPlane sampled using (z,y), (z,x) and (x,y) respectively.
            float3 volumeGrad = float3(derivZPlane.x + derivYPlane.y, derivZPlane.y + derivXplane.y, derivXplane.x + derivYPlane.x);
            return float4(SurfaceGradientFromVolumeGradient(uvMapping.vertexNormalWS, volumeGrad), normalVariance);
        }
#endif

        float4 packedNormal = SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), textureNameUV, textureNameUVLocal, textureNameST, uvMapping);
        //float4 packedNormal = SampleTexture2DScaleBiasLod(TEXTURE2D_PARAM(textureName, samplerName), textureNameUV, textureNameUVLocal, textureNameST, 1.0, uvMapping);
        float normalVariance = packedNormal.z; // If we used a tangent space normal map that store a measure of normal dispersion, the formap is RG (normal xy) and B (normal dispersion: ie variance or the average normal's length)
        float2 deriv = UnpackDerivativeNormalRGorAG(packedNormal, scale);

        if (textureNameUV <= TEXCOORD_INDEX_UV3)
        {
            return float4(SurfaceGradientFromTBN(deriv, uvMapping.vertexTangentWS[textureNameUV], uvMapping.vertexBitangentWS[textureNameUV]), normalVariance);
        }
        else
        {
            float3  volumeGrad;
            if (textureNameUV == TEXCOORD_INDEX_PLANAR_YZ)
                volumeGrad = float3(0.0, deriv.y, deriv.x);
            else if (textureNameUV == TEXCOORD_INDEX_PLANAR_ZX)
                volumeGrad = float3(deriv.y, 0.0, deriv.x);
            else if (textureNameUV == TEXCOORD_INDEX_PLANAR_XY)
                volumeGrad = float3(deriv.x, deriv.y, 0.0);

            return float4(SurfaceGradientFromVolumeGradient(uvMapping.vertexNormalWS, volumeGrad), normalVariance);
        }
    }
}
//-----------------------------------------------------------------------------
// Texture Mapping: Macros - Note the sampler sharing code need those name as is:
//-----------------------------------------------------------------------------

#define SAMPLE_TEXTURE2D_SCALE_BIAS(name) SampleTexture2DTriplanarScaleBias(name, sampler##name, name##UV, name##UVLocal, name##_ST, uvMapping)
#define SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(name, scale, objSpace) SampleTexture2DTriplanarNormalScaleBias(name, sampler##name, name##UV, name##UVLocal, name##_ST, objSpace, uvMapping, scale)
#define SAMPLE_TEXTURE2D_NORMAL_PROPNAME_SCALE_BIAS(name, propname, scale, objSpace) SampleTexture2DTriplanarNormalScaleBias(name, sampler##propname, propname##UV, propname##UVLocal, propname##_ST, objSpace, uvMapping, scale)
//...permits referencing all properties from another texture name

#define SAMPLE_TEXTURE2D_SCALE_BIAS_LOD(name, lod) SampleTexture2DScaleBiasLod(name, sampler##name, name##UV, name##UVLocal, name##_ST, lod, uvMapping) // for testing

#define SAMPLE_TEXTURE2D_SMP_SCALE_BIAS(name, samplerName) SampleTexture2DTriplanarScaleBias(name, samplerName, name##UV, name##UVLocal, name##_ST, uvMapping)
#define SAMPLE_TEXTURE2D_SMP_NORMAL_SCALE_BIAS(name, samplerName, scale, objSpace) SampleTexture2DTriplanarNormalScaleBias(name, samplerName, name##UV, name##UVLocal, name##_ST, objSpace, uvMapping, scale)
#define SAMPLE_TEXTURE2D_SMP_NORMAL_PROPNAME_SCALE_BIAS(name, samplerName, propname, scale, objSpace) SampleTexture2DTriplanarNormalScaleBias(name, samplerName, propname##UV, propname##UVLocal, propname##_ST, objSpace, uvMapping, scale)

//-----------------------------------------------------------------------------
// Texture Mapping: Sampler Sharing
//-----------------------------------------------------------------------------

#ifndef _DISABLE_SAMPLER_SHARING
#define _USE_SAMPLER_SHARING
#endif
// The following include needs those defined and uses the _USE_SAMPLER_SHARING keyword:
//
//#define SAMPLE_TEXTURE2D_SCALE_BIAS(name)
//#define SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(name, scale, objSpace)
//#define SAMPLE_TEXTURE2D_NORMAL_PROPNAME_SCALE_BIAS(name, propname, scale, objSpace)

//#define SAMPLE_TEXTURE2D_SMP_SCALE_BIAS(name, samplerName)
//#define SAMPLE_TEXTURE2D_SMP_NORMAL_SCALE_BIAS(name, samplerName, scale, objSpace)
//#define SAMPLE_TEXTURE2D_SMP_NORMAL_PROPNAME_SCALE_BIAS(name, samplerName, propname, scale, objSpace)

#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/StackLit/TextureSamplerSharing.hlsl"

// Which makes these available, which default to the first 3 above when sampler sharing
// is disabled: (eg SHARED_SAMPLING behaves like SAMPLE_TEXTURE2D_SCALE_BIAS)

//  SHARED_SAMPLING(lvalue, swizzle, useMapProperty, name)
//  SHARED_SAMPLING_NORMAL(lvalue, useMapProperty, name, scale, objSpace)
//  SHARED_SAMPLING_NORMAL_PROPNAME(lvalue, useMapProperty, name, propname, scale, objSpace)
//


//-----------------------------------------------------------------------------
// Normal Map Filtering: Tools
//-----------------------------------------------------------------------------

float4 AddDetailGradient(float4 gradient, float4 detailGradient, float detailMask)
{
    gradient.xyz += detailGradient.xyz * detailMask;

    if (_TextureNormalFilteringEnabled > 0.0)
    {
        // Note: we haven't decoded the range of the encoded variance yet, but their real
        // range is the same, so these values between [0,1] can still be added together.
        // We saturate because even though variance is not bounded, we thresholded it
        // to do the range encoding in the importer so saturate here to be consistent.
        // (see C# code NormalMapAverageLengthTexturePostprocessor.cs).
        // Multiplying a random variable by a constant increases the variance by the square of the constant ( "detailMask").
        gradient.w = saturate(gradient.w + detailGradient.w * detailMask * detailMask);
    }
    return gradient;
}

//-----------------------------------------------------------------------------
// GetSurfaceAndBuiltinData
//-----------------------------------------------------------------------------

//
// cf with
//    LitData.hlsl:GetSurfaceAndBuiltinData()
//    LitDataIndividualLayer.hlsl:GetSurfaceData( )
//    LitBuiltinData.hlsl:GetBuiltinData()
//
// Here we can combine them
//
void GetSurfaceAndBuiltinData(FragInputs input, float3 V, inout PositionInputs posInput, out SurfaceData surfaceData, out BuiltinData builtinData)
{
    // TODOTOCHECK:
#ifdef LOD_FADE_CROSSFADE // enable dithering LOD transition if user select CrossFade transition in LOD group
    uint3 fadeMaskSeed = asuint((int3)(V * _ScreenSize.xyx)); // Quantize V to _ScreenSize values
    LODDitheringTransition(fadeMaskSeed, unity_LODFade.x);
#endif

    ApplyDoubleSidedFlipOrMirror(input); // Apply double sided flip on the vertex normal.

    TextureUVMapping uvMapping; // Note this identifier is directly referenced in the SAMPLE_TEXTURE2D_* macros above
    InitializeMappingData(input, uvMapping);

    // -------------------------------------------------------------
    // Surface Data
    // -------------------------------------------------------------
    float4 sampledBaseColor = float4(1.0, 1.0, 1.0, 1.0);
    
    //if (_BaseColorUseMap) we should always sample this. In case of sampler sharing, if UseMap is not set, we consider opaque white sampled.
    {
        SHARED_SAMPLING(sampledBaseColor, rgba, _BaseColorUseMap, _BaseColorMap); //SHARED_SAMPLING(lvalue, swizzle, useMapProperty, name)
        DUMMY_USE_OF_SHARED_TEXTURES(sampledBaseColor); // basecolor is always used so a good condidate for flagging the shared samplers' textures "potentially touched" 
    }

    float alpha = sampledBaseColor.a * _BaseColor.a;
#ifdef _ALPHATEST_ON
    //NEWLITTODO: Once we include those passes in the main StackLit.shader, add handling of CUTOFF_TRANSPARENT_DEPTH_PREPASS and _POSTPASS
    // and the related properties (in the .shader) and uniforms (in the StackLitProperties file) _AlphaCutoffPrepass, _AlphaCutoffPostpass
    DoAlphaTest(alpha, _AlphaCutoff);
#endif

    // These static material feature allow compile time optimization
    surfaceData.materialFeatures = MATERIALFEATUREFLAGS_STACK_LIT_STANDARD;

    // Standard
    surfaceData.baseColor = sampledBaseColor.rgb * _BaseColor.rgb;

    float4 gradient = float4(0.0, 0.0, 0.0, 0.0);
    if (_NormalUseMap) // we don't need the test if sampler sharing is enabled, we use a switch but compiler will deal with it
    {
        //gradient = SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(_NormalMap, _NormalScale, _NormalMapObjSpace);
        SHARED_SAMPLING_NORMAL(gradient, _NormalUseMap, _NormalMap, _NormalScale, _NormalMapObjSpace);
        //DUMMY_USE_OF_SHARED_TEXTURES(gradient); 
        // normalmap is always sampled so is a good candidate for tricking the compiler on "potentially touched" texture.
        // see TextureSamplerSharing.hlsl: we disabled sharing for passes other than SHADERPASS_FORWARD, the most sampler consuming one.
    }

    float4 bentGradient = float4(gradient.x, gradient.y, gradient.z, 0.0);
    // ...last value is for normal map filtering (average normal length). Unused for bent normal for now, but
    // could be used to tilt back the bent normal to the normal and/or enlarge the visibility cone as bent visibility
    // can alias like everything else.
    // TODO
#ifdef _BENTNORMALMAP
    if (_BentNormalUseMap) // note here: we piggy back on the normal map sampler, we thus must test this here for actual assignment of the bent normal map
    {
        //bentGradient = SAMPLE_TEXTURE2D_NORMAL_PROPNAME_SCALE_BIAS(_BentNormalMap, _NormalMap, _NormalScale, _NormalMapObjSpace);
        SHARED_SAMPLING_NORMAL_PROPNAME(bentGradient, _NormalUseMap, _BentNormalMap, _NormalMap, _NormalScale, _NormalMapObjSpace);
        // ...note above how we use "_NormalUseMap" and NOT "_BentNormalUseMap" for the sampler number to use!
    }
#endif

    surfaceData.perceptualSmoothnessA = _SmoothnessA;
    if (_SmoothnessAUseMap) // we still need to escape the dot if we dont sample
    {
        float4 tmp = (float4)0;

        //SHARED_SAMPLING(lvalue, swizzle, useMapProperty, name)
        SHARED_SAMPLING(tmp, rgba, _SmoothnessAUseMap, _SmoothnessAMap);
        //surfaceData.perceptualSmoothnessA = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_SmoothnessAMap), _SmoothnessAMapChannelMask);
        surfaceData.perceptualSmoothnessA = dot(tmp, _SmoothnessAMapChannelMask);
        surfaceData.perceptualSmoothnessA = lerp(_SmoothnessAMapRange.x, _SmoothnessAMapRange.y, surfaceData.perceptualSmoothnessA);
    }
    //surfaceData.perceptualSmoothnessA = lerp(_SmoothnessA, surfaceData.perceptualSmoothnessA, _SmoothnessAUseMap);

    // Metallic / specular color
    surfaceData.dielectricIor = _DielectricIor; // shouldn't be needed if _MATERIAL_FEATURE_SPECULAR_COLOR
    // debug test, to visualize the dispersion measure of the normal map:
    //surfaceData.dielectricIor = gradient.w;
    surfaceData.specularColor = float3(1.0, 1.0, 1.0);
    surfaceData.metallic = 0.0;
#ifdef _MATERIAL_FEATURE_SPECULAR_COLOR
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_SPECULAR_COLOR;
    surfaceData.specularColor = _SpecularColor.rgb;
    if (_SpecularColorUseMap)
    {
        float3 tmp = (float3)0;
        SHARED_SAMPLING(tmp, rgb, _SpecularColorUseMap, _SpecularColorMap);
        surfaceData.specularColor *= tmp;
    }
    // Reproduce the energy conservation done in legacy Unity. Not ideal but better for compatibility and users can unchek it
    surfaceData.baseColor *= _EnergyConservingSpecularColor > 0.0 ? (1.0 - Max3(surfaceData.specularColor.r, surfaceData.specularColor.g, surfaceData.specularColor.b)) : 1.0;
#else
    surfaceData.metallic = _Metallic;
    if (_MetallicUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _MetallicUseMap, _MetallicMap);
        surfaceData.metallic = dot(tmp, _MetallicMapChannelMask);
        surfaceData.metallic = lerp(_MetallicMapRange.x, _MetallicMapRange.y, surfaceData.metallic);
    }
#endif

    // Ambient Occlusion
    surfaceData.ambientOcclusion = _AmbientOcclusion;
    if (_AmbientOcclusionUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _AmbientOcclusionUseMap, _AmbientOcclusionMap);
        surfaceData.ambientOcclusion = dot(tmp, _AmbientOcclusionMapChannelMask);
        surfaceData.ambientOcclusion = lerp(_AmbientOcclusionMapRange.x, _AmbientOcclusionMapRange.y, surfaceData.ambientOcclusion);
    }

    // Dual specular lobe
    surfaceData.lobeMix = 0.0;
    surfaceData.perceptualSmoothnessB = 1.0;
    surfaceData.haziness = 0.0;
    surfaceData.hazeExtent = 0.0;
    surfaceData.hazyGlossMaxDielectricF0 = 1.0;

#ifdef _MATERIAL_FEATURE_DUAL_SPECULAR_LOBE
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_DUAL_SPECULAR_LOBE;
#ifdef _MATERIAL_FEATURE_HAZY_GLOSS
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_HAZY_GLOSS;

    surfaceData.haziness = _Haziness;
    if (_HazinessUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _HazinessUseMap, _HazinessMap);
        surfaceData.haziness = dot(tmp, _HazinessMapChannelMask);
        surfaceData.haziness = lerp(_HazinessMapRange.x, _HazinessMapRange.y, surfaceData.haziness);
    }

    surfaceData.hazeExtent = _HazeExtent;
    if (_HazeExtentUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _HazeExtentUseMap, _HazeExtentMap);
        surfaceData.hazeExtent = dot(tmp, _HazeExtentMapChannelMask);
        surfaceData.hazeExtent = lerp(_HazeExtentMapRange.x, _HazeExtentMapRange.y, surfaceData.hazeExtent);
    }
    surfaceData.hazeExtent *= _HazeExtentMapRangeScale;
#ifndef _MATERIAL_FEATURE_SPECULAR_COLOR
    // base parametrization is baseColor + metallic, use value / option regarding how high can hazeExtent and f0 go:
    // If metallic parametrization is actually used, set the cap to be enforced later by the hazy gloss mapping,
    // it will be adjusted according to the metallic value such that
    // hazyGlossMaxf0 = ComputeFresnel0(1.0, surfaceData.metallic, surfaceData.hazyGlossMaxDielectricF0);
    surfaceData.hazyGlossMaxDielectricF0 = _HazyGlossMaxDielectricF0;
#else
    surfaceData.hazyGlossMaxDielectricF0 = 1.0;
#endif

#else // else not def _MATERIAL_FEATURE_HAZY_GLOSS
    surfaceData.lobeMix = _LobeMix;
    if (_LobeMixUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _LobeMixUseMap, _LobeMixMap);
        surfaceData.lobeMix = dot(tmp, _LobeMixMapChannelMask);
        surfaceData.lobeMix = lerp(_LobeMixMapRange.x, _LobeMixMapRange.y, surfaceData.lobeMix);
    }

    surfaceData.perceptualSmoothnessB = _SmoothnessB;
    if (_SmoothnessBUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _SmoothnessBUseMap, _SmoothnessBMap);
        surfaceData.perceptualSmoothnessB = dot(tmp, _SmoothnessBMapChannelMask);
        surfaceData.perceptualSmoothnessB = lerp(_SmoothnessBMapRange.x, _SmoothnessBMapRange.y, surfaceData.perceptualSmoothnessB);
    }
#endif // _MATERIAL_FEATURE_HAZY_GLOSS
#endif // _MATERIAL_FEATURE_DUAL_SPECULAR_LOBE


    surfaceData.anisotropyA = 0.0;
    surfaceData.anisotropyB = 0.0;
#ifdef _MATERIAL_FEATURE_ANISOTROPY
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_ANISOTROPY;
    // cf. with the Lit shader: 
    // We don't multiply the _Anisotropy property with the map, as our UI has a range remapping slider
    // that has limits of -1 to 1. By default, the remap range (that maps the texture [0,1] range to
    // another interval) is set from 0 to 1 with the UI looking like this:
    //
    // -1[.....======]+1
    // [ ] invert remapping
    //
    // so as coded below, the [0,1] range of the map is mapped to the same.
    // If anisotropy along the other axis is wanted, the interval segment of the UI can be dragged to
    // cover -1 to 0 and the invert toggle checked, so that [0,1] is mapped to values from 0 to -1,
    // with the UI looking as such:
    //
    // -1[======.....]+1
    // [x] invert remapping
    //
    // Finally, any dampening of the effect of the map that can be obtained by multiplication by the
    // scalar _Anisotropy propery as done in Lit can be obtained here by dragging the extreme end of the
    // segment of the range slider (the end closer to +1 or -1 in the above configurations) so that the
    // UI would look like this
    //
    // -1[.....====..]+1
    // [ ] invert remapping
    //
    // or this:
    //
    // -1[..====.....]+1
    // [x] invert remapping
    //
    surfaceData.anisotropyA = _AnisotropyA;
    if (_AnisotropyAUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _AnisotropyAUseMap, _AnisotropyAMap);
        surfaceData.anisotropyA = dot(tmp, _AnisotropyAMapChannelMask);
        surfaceData.anisotropyA = lerp(_AnisotropyAMapRange.x, _AnisotropyAMapRange.y, surfaceData.anisotropyA);
    }
#ifdef _MATERIAL_FEATURE_DUAL_SPECULAR_LOBE
    surfaceData.anisotropyB = _AnisotropyB;
    if (_AnisotropyBUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _AnisotropyBUseMap, _AnisotropyBMap);
        surfaceData.anisotropyB = dot(tmp, _AnisotropyBMapChannelMask);
        surfaceData.anisotropyB = lerp(_AnisotropyBMapRange.x, _AnisotropyBMapRange.y, surfaceData.anisotropyB);
    }
#endif
#endif // _MATERIAL_FEATURE_ANISOTROPY

    // Note we don't normalize tangentWS either with a tangentmap or using the interpolated tangent from the TBN frame
    // as it will be normalized later with a call to Orthonormalize().
    surfaceData.tangentWS = input.worldToTangent[0].xyz; // The tangent is not normalize in worldToTangent for mikkt. TODO: Check if it expected that we normalize with Morten. Tag: SURFACE_GRADIENT
#ifdef _TANGENTMAP
    if (_TangentUseMap)
    {
        float4 tmp = (float4)0;
        // If using the normal sampling macro, we will get a WS gradient and we must not call Transform*ToWorld,
        SHARED_SAMPLING_NORMAL(tmp, _TangentUseMap, _TangentMap, /*scale*/ 1.0, _TangentMapObjSpace);
        // but we need to resolve at the end with SurfaceGradientResolveNormal():
        surfaceData.tangentWS = SurfaceGradientResolveNormal(input.worldToTangent[2], tmp.xyz);
        #if 0
        // We can also skip gradients and unpack and transform here:
        SHARED_SAMPLING(tmp, rgba, _TangentUseMap, _TangentMap);
        if (_TangentMapObjSpace)
        {
            tmp.xyz = UnpackNormalRGB(tmp);
            surfaceData.tangentWS = TransformObjectToWorldDir(tmp.xyz);
        }
        else
        {
            tmp.xyz = UnpackNormalmapRGorAG(tmp);
            surfaceData.tangentWS = TransformTangentToWorld(tmp.xyz, input.worldToTangent);
        }
        #endif
    }
#endif

    float4 coatGradient = float4(0.0, 0.0, 0.0, 0.0);
#ifdef _MATERIAL_FEATURE_COAT
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_COAT;

    surfaceData.coatPerceptualSmoothness = _CoatSmoothness;
    if (_CoatSmoothnessUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _CoatSmoothnessUseMap, _CoatSmoothnessMap);
        surfaceData.coatPerceptualSmoothness = dot(tmp, _CoatSmoothnessMapChannelMask);
        surfaceData.coatPerceptualSmoothness = lerp(_CoatSmoothnessMapRange.x, _CoatSmoothnessMapRange.y, surfaceData.coatPerceptualSmoothness);
    }

    surfaceData.coatIor = _CoatIor;
    if (_CoatIorUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _CoatIorUseMap, _CoatIorMap);
        surfaceData.coatIor = dot(tmp, _CoatIorMapChannelMask);
        surfaceData.coatIor = lerp(_CoatIorMapRange.x, _CoatIorMapRange.y, surfaceData.coatIor);
    }

    surfaceData.coatThickness = _CoatThickness;
    if (_CoatThicknessUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _CoatThicknessUseMap, _CoatThicknessMap);
        surfaceData.coatThickness = dot(tmp, _CoatThicknessMapChannelMask);
        surfaceData.coatThickness = lerp(_CoatThicknessMapRange.x, _CoatThicknessMapRange.y, surfaceData.coatThickness);
    }

    surfaceData.coatExtinction = _CoatExtinction; // in thickness^-1 units
    if (_CoatExtinctionUseMap)
    {
        float3 tmp = (float3)0;
        SHARED_SAMPLING(tmp, rgb, _CoatExtinctionUseMap, _CoatExtinctionMap);
        surfaceData.coatExtinction *= tmp;
    }

#ifdef _MATERIAL_FEATURE_COAT_NORMALMAP
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_COAT_NORMAL_MAP;
    if (_CoatNormalUseMap)
    {
        //coatGradient = SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(_CoatNormalMap, _CoatNormalScale, _CoatNormalMapObjSpace);
        SHARED_SAMPLING_NORMAL(coatGradient, _CoatNormalUseMap, _CoatNormalMap, _CoatNormalScale, _CoatNormalMapObjSpace);
    }
#endif

#else
    surfaceData.coatPerceptualSmoothness = 0.0;
    surfaceData.coatIor = 1.0001;
    surfaceData.coatThickness = 0.0;
    surfaceData.coatExtinction = float3(1.0, 1.0, 1.0);
#endif // _MATERIAL_FEATURE_COAT

#ifdef _MATERIAL_FEATURE_IRIDESCENCE
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_IRIDESCENCE;
    surfaceData.iridescenceIor = _IridescenceIor;

    surfaceData.iridescenceThickness = _IridescenceThickness;
    if (_IridescenceThicknessUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _IridescenceThicknessUseMap, _IridescenceThicknessMap);
        surfaceData.iridescenceThickness = dot(tmp, _IridescenceThicknessMapChannelMask);
        surfaceData.iridescenceThickness = lerp(_IridescenceThicknessMapRange.x, _IridescenceThicknessMapRange.y, surfaceData.iridescenceThickness);
    }

    surfaceData.iridescenceMask = _IridescenceMask;
    if (_IridescenceMaskUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _IridescenceMaskUseMap, _IridescenceMaskMap);
        surfaceData.iridescenceMask = dot(tmp, _IridescenceMaskMapChannelMask);
        surfaceData.iridescenceMask = lerp(_IridescenceMaskMapRange.x, _IridescenceMaskMapRange.y, surfaceData.iridescenceMask);
    }

#else
    surfaceData.iridescenceIor = 1.0;
    surfaceData.iridescenceThickness = 0.0;
    surfaceData.iridescenceMask = 0.0;
#endif

#if defined(_MATERIAL_FEATURE_SUBSURFACE_SCATTERING) || defined(_MATERIAL_FEATURE_TRANSMISSION)
    surfaceData.diffusionProfile = _DiffusionProfile;
#else
    surfaceData.diffusionProfile = 0;
#endif

#ifdef _MATERIAL_FEATURE_SUBSURFACE_SCATTERING
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_SUBSURFACE_SCATTERING;

    surfaceData.subsurfaceMask = _SubsurfaceMask;
    if (_SubsurfaceMaskUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _SubsurfaceMaskUseMap, _SubsurfaceMaskMap);
        surfaceData.subsurfaceMask = dot(tmp, _SubsurfaceMaskMapChannelMask);
        surfaceData.subsurfaceMask = lerp(_SubsurfaceMaskMapRange.x, _SubsurfaceMaskMapRange.y, surfaceData.subsurfaceMask);
    }
#else
    surfaceData.subsurfaceMask = 0.0;
#endif

#ifdef _MATERIAL_FEATURE_TRANSMISSION
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_TRANSMISSION;

    surfaceData.thickness = _Thickness;
    if (_ThicknessUseMap)
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _ThicknessUseMap, _ThicknessMap);
        surfaceData.thickness = dot(tmp, _ThicknessMapChannelMask);
        surfaceData.thickness = lerp(_ThicknessMapRange.x, _ThicknessMapRange.y, surfaceData.thickness);
    }
#else
    surfaceData.thickness = 1.0;
#endif

#ifdef _DETAILMAP
    //float detailMask = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_DetailMaskMap), _DetailMaskMapChannelMask);
    float detailMask;
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _DetailMaskUseMap, _DetailMaskMap);
        detailMask = dot(tmp, _DetailMaskMapChannelMask);
    }

    float4 detailGradient = float4(0.0, 0.0, 0.0, 0.0);
    if (_DetailNormalUseMap)
    {
        //detailGradient = SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(_DetailNormalMap, _DetailNormalScale, 0.0);
        SHARED_SAMPLING_NORMAL(detailGradient, _DetailNormalUseMap, _DetailNormalMap, _DetailNormalScale, 0.0);
    }

    gradient = AddDetailGradient(gradient, detailGradient, detailMask);
    bentGradient = AddDetailGradient(bentGradient, detailGradient, detailMask);

    //float detailPerceptualSmoothness = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_DetailSmoothnessMap), _DetailSmoothnessMapChannelMask);
    float detailPerceptualSmoothness;
    {
        float4 tmp = (float4)0;
        SHARED_SAMPLING(tmp, rgba, _DetailSmoothnessUseMap, _DetailSmoothnessMap);
        detailPerceptualSmoothness = dot(tmp, _DetailSmoothnessMapChannelMask);
    }
    //debug: TODO either lineargrey or grey won't give 0.5 but 0.215 or 0.211
    //surfaceData.dielectricIor = detailPerceptualSmoothness;
    detailPerceptualSmoothness = lerp(_DetailSmoothnessMapRange.x, _DetailSmoothnessMapRange.y, detailPerceptualSmoothness);

    // We assume here that 0 <= _DetailSmoothnessMapRange.x < _DetailSmoothnessMapRange.y <= 1
    // (ie _DetailSmoothnessMapRemap should be (0,1) in the shader so the user can't set the remap endpoints outside this in the UI)
    // such that 0 <= detailPerceptualSmoothness <= 1 (numerical calculations implied by lerp might violate the later though)
    detailPerceptualSmoothness = detailPerceptualSmoothness * 2.0 - 1.0;
    /// remap [0,1] to [-1, 1] : positive values will push the final smoothness (absolutely) towards 1 and negative values toward 0.

    // Use overlay blend mode for detail:
    //
    // detailPerceptualSmoothness * _DetailSmoothnessScale from 0 to -1 controls a new absolute value for the smoothness
    // that is closer to the absolute 0.0 endpoint (it is linearly relative to the original smoothness and the slope of the
    // effect of the range of detailPerceptualSmoothness in [-1 to 0] is controlled by _DetailSmoothnessScale).
    // Likewise, for positive detailPerceptualSmoothness, the 0 to +1 range calculates a new value towards the 1.0 endpoint.
    //
    // So (detailPerceptualSmoothness distance from 0) * _DetailSmoothnessScale controls the new endpoint, and the detailMask
    // controls interpolation between the original smoothness value and the new endpoint calculated. Of course since both interpolations
    // are linear, the slope of the effect depends on both _DetailSmoothnessScale and detailMask, although because of saturation
    // in between, _DetailSmoothnessScale can be viewed as a thresholding control on the detail map before the application of
    // the mask interpolation.
    float smoothnessDetailSpeed = saturate(abs(detailPerceptualSmoothness) * _DetailSmoothnessScale);
    float smoothnessOverlay = lerp(surfaceData.perceptualSmoothnessA, (detailPerceptualSmoothness < 0.0) ? 0.0 : 1.0, smoothnessDetailSpeed);

    // Lerp with details mask
    surfaceData.perceptualSmoothnessA = lerp(surfaceData.perceptualSmoothnessA, saturate(smoothnessOverlay), detailMask);

    #ifdef _MATERIAL_FEATURE_DUAL_SPECULAR_LOBE
    // Note that this will be ignored when using Hazy Gloss parametrization.
    // This could be translated to apply to hazeExtent instead if we really want that control, but conceptually,
    // since smoothnessB depends on hazeExtent and smoothnessA only, it makes sense to not additionally covary hazeExtent.
    // See also the case of specular AA below.


    smoothnessOverlay = lerp(surfaceData.perceptualSmoothnessB, (detailPerceptualSmoothness < 0.0) ? 0.0 : 1.0, smoothnessDetailSpeed);
    // Lerp with details mask
    surfaceData.perceptualSmoothnessB = lerp(surfaceData.perceptualSmoothnessB, saturate(smoothnessOverlay), detailMask);
    #endif
#endif
    // -------------------------------------------------------------
    // Surface Data Part 2 (outsite GetSurfaceData( ) in Lit shader):
    // -------------------------------------------------------------

    surfaceData.geomNormalWS = input.worldToTangent[2];
    // Convert back to world space normal
    surfaceData.normalWS = SurfaceGradientResolveNormal(input.worldToTangent[2], gradient.xyz);
    surfaceData.bentNormalWS = SurfaceGradientResolveNormal(input.worldToTangent[2], bentGradient.xyz);
    surfaceData.coatNormalWS = SurfaceGradientResolveNormal(input.worldToTangent[2], coatGradient.xyz);

    // tangentWS will not be normalized at this point (whether coming from input.worldToTangent[0] or a tangent map),
    // but this is ok as the Orthonormalize() call here will:
    surfaceData.tangentWS = Orthonormalize(surfaceData.tangentWS, surfaceData.normalWS);

    // TODO: Improve StackLitDecalData (also, problem with TextureNormalFiltering)
#if HAVE_DECALS
    if (_EnableDecals)
    {
        DecalSurfaceData decalSurfaceData = GetDecalSurfaceData(posInput, alpha);
        ApplyDecalToSurfaceData(decalSurfaceData, surfaceData);
    }
#endif

    if ((_GeometricNormalFilteringEnabled + _TextureNormalFilteringEnabled) > 0.0)
    {
        // TODO Note: specular occlusion that uses bent normals should also use filtering, although the visibility model is not a
        // specular lobe with roughness but a cone with solid angle determined by the ambient occlusion so this is an even more
        // empirical hack (with visibility modelled by a single circular region in direction space)
        // Intuitively, an increase of variance should enlarge (possible) visibility and thus diminish the occlusion
        // (enlarge the visibility cone). This goes in hand with the softer BSDF specular lobe.

        // See remark about _DETAILMAP when in hazy gloss mode above:
        // Note that when using the Hazy Gloss parametrization, the user has no direct control on smoothnessB, and
        // surfaceData.perceptualSmoothnessB will be 0 in that case.
        // Conceptually, in that mode smoothnessB now depends on hazeExtent and smoothnessA only, and hazeExtent is
        // a perceptual control in that "smoothnessB from smoothnessA" dependency (it will also influence lobeMix and the new
        // f0 for the base layer precisely via smoothnessB). Finally, in that parametrization, smoothnessB is always <= smoothnessA.
        // It thus makes sense to only modify smoothnessA while doing SpecularAA, the hazemapping takes care of the rest.
        // The compiler should prune out our calculations for surfaceData.perceptualSmoothnessB in that case since it will never
        // be read before being overwritten later.

        float geometricVariance = _GeometricNormalFilteringEnabled ? GeometricNormalVariance(input.worldToTangent[2], _SpecularAntiAliasingScreenSpaceVariance) : 0.0;
        float textureFilteringVariance = _TextureNormalFilteringEnabled ? DecodeVariance(gradient.w) : 0.0;
        float coatTextureFilteringVariance = _TextureNormalFilteringEnabled ? DecodeVariance(coatGradient.w) : 0.0;

        surfaceData.perceptualSmoothnessA = NormalFiltering(surfaceData.perceptualSmoothnessA, geometricVariance + textureFilteringVariance, _SpecularAntiAliasingThreshold);
        surfaceData.perceptualSmoothnessB = NormalFiltering(surfaceData.perceptualSmoothnessB, geometricVariance + textureFilteringVariance, _SpecularAntiAliasingThreshold);
        surfaceData.coatPerceptualSmoothness = NormalFiltering(surfaceData.coatPerceptualSmoothness, geometricVariance + coatTextureFilteringVariance, _SpecularAntiAliasingThreshold);
    }

#if defined(DEBUG_DISPLAY)
    if (_DebugMipMapMode != DEBUGMIPMAPMODE_NONE)
    {
        if (_BaseColorMapUV != TEXCOORD_INDEX_TRIPLANAR)
        {
            surfaceData.baseColor = GetTextureDataDebug(_DebugMipMapMode, uvMapping.texcoords[_BaseColorMapUV][_BaseColorMapUVLocal], _BaseColorMap, _BaseColorMap_TexelSize, _BaseColorMap_MipInfo, surfaceData.baseColor);
        }
        else
        {
            surfaceData.baseColor = float3(0.0, 0.0, 0.0);
        }
        surfaceData.metallic = 0.0;
    }

    // We need to call ApplyDebugToSurfaceData after filling the surfarcedata and before filling builtinData
    // as it can modify attributes used for static lighting
    ApplyDebugToSurfaceData(input.worldToTangent, surfaceData);
#endif

    // -------------------------------------------------------------
    // Builtin Data:
    // -------------------------------------------------------------

    // For back lighting we use the oposite vertex normal
    // Like in Lit (see LitBuiltinData), we use the bentNormalWS direction for the normal to use for baked data.
    InitBuiltinData(alpha, surfaceData.bentNormalWS, -input.worldToTangent[2], input.positionRWS, input.texCoord1, input.texCoord2, builtinData);

    builtinData.emissiveColor = _EmissiveColor * lerp(float3(1.0, 1.0, 1.0), surfaceData.baseColor.rgb, _AlbedoAffectEmissive);
    if (_EmissiveColorUseMap)
    {
        float3 tmp = (float3)0;
        SHARED_SAMPLING(tmp, rgb, _EmissiveColorUseMap, _EmissiveColorMap);
        builtinData.emissiveColor *= tmp;
    }

#if (SHADERPASS == SHADERPASS_DISTORTION) || defined(DEBUG_DISPLAY)
    float3 distortion = SAMPLE_TEXTURE2D(_DistortionVectorMap, sampler_DistortionVectorMap, input.texCoord0.xy).rgb;
    distortion.rg = distortion.rg * _DistortionVectorScale.xx + _DistortionVectorBias.xx;
    builtinData.distortion = distortion.rg * _DistortionScale;
    builtinData.distortionBlur = clamp(distortion.b * _DistortionBlurScale, 0.0, 1.0) * (_DistortionBlurRemapMax - _DistortionBlurRemapMin) + _DistortionBlurRemapMin;
#endif

    PostInitBuiltinData(V, posInput, surfaceData, builtinData);
}
