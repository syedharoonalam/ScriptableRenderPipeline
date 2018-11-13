using System;
using System.Runtime.InteropServices.ComTypes;
using System.Xml.Schema;
using UnityEngine;

namespace UnityEditor
{
    public abstract class BaseShaderGUI : ShaderGUI
    {
        public enum SurfaceType
        {
            Opaque,
            Transparent
        }

        public enum BlendMode
        {
            Alpha,   // Old school alpha-blending mode, fresnel does not affect amount of transparency
            Premultiply, // Physically plausible transparency mode, implemented as alpha pre-multiply
            Additive,
            Multiply
        }
        
        public enum SmoothnessSource
        {
            BaseAlpha,
            SpecularAlpha
        }

        public enum Culling
        {
            BackFace = 2,
            FrontFace = 1,
            Off = 0
        }

        protected class Styles
        {
            // Catergories
            public static readonly GUIContent SurfaceOptions = new GUIContent("Surface Options", "Tooltip");
            public static readonly GUIContent SurfaceInputs = new GUIContent("Surface Inputs", "Tooltip");
            public static readonly GUIContent AdvancedLabel = new GUIContent("Advanced", "Tooltip");
            
            public static readonly GUIContent surfaceType = new GUIContent("Surface Type", "Tooltip");
            public static readonly GUIContent blendingMode = new GUIContent("Blending Mode", "Tooltip");
            public static readonly GUIContent twoSidedText = new GUIContent("Double-sided", "Enable to render both front and back faces, disable to cull the back faces");
            public static readonly GUIContent cullingText = new GUIContent("Face Culling", "Choose the culling option for this material.");
            public static readonly GUIContent alphaClipText = new GUIContent("Alpha Clipping", "Enables Alpha Clipping on this material, this uses the alpha value of the Base Map and Base Color, use the threshold to adjust the bias.");
            public static readonly GUIContent alphaClipThresholdText = new GUIContent("Threshold", "Acts as an offset for the alpha clip");
            public static readonly GUIContent receiveShadowText = new GUIContent("Receive Shadows", "Enables this material to receive shadows if there is at least one shadow casting light affecting it.");
            
            public static readonly GUIContent baseMap = new GUIContent("Base Map", "This Property is used for adding base coloring to the material.\n" +
                                                                      "If there is no RGB texture map assigned the color property is used, otherwise it is multiplied over the texture map.");
            public static readonly GUIContent baseColor = new GUIContent("Base Color", "This color property adds base coloring to the material, if a Base Map is assigned this color will be multiplied over it.");
            public static readonly GUIContent emissionMap = new GUIContent("Emission Map", "This Property is used for adding emissive light to the material.\n" +
                                                                              "If there is no RGB texture map assigned the color property controls the emission, otherwise it is multiplied over the texture map.");
            public static readonly GUIContent emissionColor = new GUIContent("Emission Color", "This color property adds emissive to the material, if a Base Map is assigned this color will be multiplied over it.");
            
            public static readonly GUIContent normalMapText = new GUIContent("Normal Map", "Normal Map");
            public static readonly GUIContent bumpScaleNotSupported = new GUIContent("Bump scale is not supported on mobile platforms");
            public static readonly GUIContent fixNow = new GUIContent("Fix now");
            
            public static readonly GUIContent queueSlider = new GUIContent("Queue Offset", "This slider controls the offset in the render queue, use this for fine tuning render order.");
        }

        protected MaterialEditor materialEditor { get; set; }
        protected MaterialProperty surfaceTypeProp { get; set; }
        protected MaterialProperty blendModeProp { get; set; }
        protected MaterialProperty cullingProp { get; set; }
        protected MaterialProperty alphaClipProp { get; set; }
        protected MaterialProperty alphaCutoffProp { get; set; }
        protected MaterialProperty receiveShadowsProp { get; set; }
        // Common Surface Input properties
        protected MaterialProperty baseMapProp { get; set; }
        protected MaterialProperty baseColorProp { get; set; }
        protected MaterialProperty emissionMapProp { get; set; }
        protected MaterialProperty emissionColorProp { get; set; }
        protected MaterialProperty queueOffsetProp { get; set; }
        public bool m_FirstTimeApply = true;

        private const string k_KeyPrefix = "LightweightRP:Material:UI_State:";
        private string m_HeaderStateKey = null;
        protected uint defaultHeaderState = 0;
        private const int queueOffsetRange = 50;

        public abstract void MaterialChanged(Material material);

        public virtual void FindProperties(MaterialProperty[] properties)
        {
            surfaceTypeProp = FindProperty("_Surface", properties);
            blendModeProp = FindProperty("_Blend", properties);
            cullingProp = FindProperty("_Cull", properties);
            alphaClipProp = FindProperty("_AlphaClip", properties);
            alphaCutoffProp = FindProperty("_Cutoff", properties);
            receiveShadowsProp = FindProperty("_ReceiveShadows", properties, false);
            baseMapProp = FindProperty("_BaseMap", properties, false);
            baseColorProp = FindProperty("_BaseColor", properties, false);
            emissionMapProp = FindProperty("_EmissionMap", properties, false);
            emissionColorProp = FindProperty("_EmissionColor", properties, false);
            queueOffsetProp = FindProperty("_QueueOffset", properties, false);
        }

        public void ShaderPropertiesGUI(Material material)
        {
            if (material == null)
                throw new ArgumentNullException("material");

            var surfaceState = EditorGUILayout.BeginFoldoutHeaderGroup(GetHeaderState(0), Styles.SurfaceOptions);
            if(surfaceState){
                EditorGUI.BeginChangeCheck();
                DrawSurfaceOptions(material);
                if (EditorGUI.EndChangeCheck())
                    MaterialChanged(material);
                EditorGUILayout.Space();
            }
            EditorGUILayout.EndFoldoutHeaderGroup();
            StoreHeaderState(surfaceState, 0);

            var inputState = EditorGUILayout.BeginFoldoutHeaderGroup(GetHeaderState(1), Styles.SurfaceInputs);
            if (inputState)
            {
                EditorGUI.BeginChangeCheck();
                DrawSurfaceInputs(material);
                if (EditorGUI.EndChangeCheck())
                    MaterialChanged(material);
                EditorGUILayout.Space();
            }
            EditorGUILayout.EndFoldoutHeaderGroup();
            StoreHeaderState(inputState, 1);

            var advanced = EditorGUILayout.BeginFoldoutHeaderGroup(GetHeaderState(2), Styles.AdvancedLabel);
            if (advanced)
            {
                EditorGUI.BeginChangeCheck();
                DrawAdvancedOptions(material);
                if (EditorGUI.EndChangeCheck())
                    MaterialChanged(material);
            }
            EditorGUILayout.EndFoldoutHeaderGroup();
            StoreHeaderState(advanced, 2);

            EditorGUI.BeginChangeCheck();
            DrawAdditionalFoldouts(material);
            if (EditorGUI.EndChangeCheck())
                MaterialChanged(material);
        }

        public override void OnGUI(MaterialEditor materialEditorIn, MaterialProperty[] properties)
        {
            if (materialEditorIn == null)
                throw new ArgumentNullException("materialEditorIn");

            FindProperties(properties); // MaterialProperties can be animated so we do not cache them but fetch them every event to ensure animated values are updated correctly
            materialEditor = materialEditorIn;
            Material material = materialEditor.target as Material;
            m_HeaderStateKey = k_KeyPrefix + material.shader.name; // Create key string for editor prefs

            // Make sure that needed setup (ie keywords/renderqueue) are set up if we're switching some existing
            // material to a lightweight shader.
            if (m_FirstTimeApply)
            {
                MaterialChanged(material);
                m_FirstTimeApply = false;
            }

            ShaderPropertiesGUI(material);
        }

        public virtual void DrawSurfaceOptions(Material material)
        {
            DoPopup(Styles.surfaceType, surfaceTypeProp, Enum.GetNames(typeof(SurfaceType)));
            if ((SurfaceType)material.GetFloat("_Surface") == SurfaceType.Transparent)
                DoPopup(Styles.blendingMode, blendModeProp, Enum.GetNames(typeof(BlendMode)));

            EditorGUI.BeginChangeCheck();
            var culling = (Culling)cullingProp.floatValue;
            culling = (Culling)EditorGUILayout.EnumPopup(Styles.cullingText, culling);
            if (EditorGUI.EndChangeCheck())
            {
                cullingProp.floatValue = (float)culling;
                material.doubleSidedGI = culling != Culling.BackFace;
            }

            EditorGUI.BeginChangeCheck();
            var alphaClipEnabled = EditorGUILayout.Toggle(Styles.alphaClipText, alphaClipProp.floatValue == 1);
            if (EditorGUI.EndChangeCheck())
                alphaClipProp.floatValue = alphaClipEnabled ? 1 : 0;

            if (alphaClipProp.floatValue == 1)
                materialEditor.ShaderProperty(alphaCutoffProp, Styles.alphaClipThresholdText, 1);

            if (receiveShadowsProp != null)
            {
                EditorGUI.BeginChangeCheck();
                var receiveShadows =
                    EditorGUILayout.Toggle(Styles.receiveShadowText, receiveShadowsProp.floatValue == 1.0f);
                if (EditorGUI.EndChangeCheck())
                    receiveShadowsProp.floatValue = receiveShadows ? 1.0f : 0.0f;
            }
        }

        public virtual void DrawSurfaceInputs(Material material)
        {
            DrawBaseProperties();
        }

        public virtual void DrawAdvancedOptions(Material material)
        {
            materialEditor.EnableInstancingField();

/*            if (queueOffsetProp != null)
            {
                queueOffsetProp.floatValue = EditorGUILayout.IntSlider(Styles.queueSlider, (int)queueOffsetProp.floatValue, -queueOffsetRange, queueOffsetRange);
            }*/
        }

        public virtual void DrawBaseProperties()
        {
            if (baseMapProp != null && baseColorProp != null) // Draw the baseMap, most shader will have at least a baseMap
            {
                materialEditor.TexturePropertySingleLine(Styles.baseMap, baseMapProp, baseColorProp);
            }
        }
        
        public virtual void DrawEmissionProperties(Material material, bool keyword)
        {
            var emissive = true;
            var hadEmissionTexture = emissionMapProp.textureValue != null;

            if (!keyword)
            {
                materialEditor.TexturePropertyWithHDRColor(Styles.emissionMap, emissionMapProp, emissionColorProp,
                    false);
            }
            else
            {
                // Emission for GI?
                emissive = materialEditor.EmissionEnabledProperty();

                EditorGUI.BeginDisabledGroup(!emissive);
                {
                    // Texture and HDR color controls
                    materialEditor.TexturePropertyWithHDRColor(Styles.emissionMap, emissionMapProp,
                        emissionColorProp,
                        false);
                }
                EditorGUI.EndDisabledGroup();
            }

            // If texture was assigned and color was black set color to white
            var brightness = emissionColorProp.colorValue.maxColorComponent;
            if (emissionMapProp.textureValue != null && !hadEmissionTexture && brightness <= 0f)
                emissionColorProp.colorValue = Color.white;

            // LW does not support RealtimeEmissive. We set it to bake emissive and handle the emissive is black right.
            if (emissive)
            {
                material.globalIlluminationFlags = MaterialGlobalIlluminationFlags.BakedEmissive;
                if (brightness <= 0f)
                    material.globalIlluminationFlags |= MaterialGlobalIlluminationFlags.EmissiveIsBlack;
            }
        }
        
        public static void DoNormalArea(MaterialEditor materialEditor, MaterialProperty bumpMap, MaterialProperty bumpMapScale = null)
        {
            if (bumpMapScale != null)
            {
                materialEditor.TexturePropertySingleLine(Styles.normalMapText, bumpMap,
                    bumpMap.textureValue != null ? bumpMapScale : null);
                if (bumpMapScale.floatValue != 1 &&
                    UnityEditorInternal.InternalEditorUtility.IsMobilePlatform(
                        EditorUserBuildSettings.activeBuildTarget))
                    if (materialEditor.HelpBoxWithButton(Styles.bumpScaleNotSupported, Styles.fixNow))
                        bumpMapScale.floatValue = 1;
            }
            else
            {
                materialEditor.TexturePropertySingleLine(Styles.normalMapText, bumpMap);
            }
        }

        public virtual void DrawAdditionalFoldouts(Material material){}

        public void DrawBaseTileOffset()
        {
            materialEditor.TextureScaleOffsetProperty(baseMapProp);
        }

        public static void SetupMaterialBlendMode(Material material)
        {
            if (material == null)
                throw new ArgumentNullException("material");

            bool alphaClip = material.GetFloat("_AlphaClip") == 1;
            if (alphaClip)
            {
                material.EnableKeyword("_ALPHATEST_ON");
            }
            else
            {
                material.DisableKeyword("_ALPHATEST_ON");
            }

            var queueOffset = 0; // queueOffsetRange;
            //if(material.HasProperty("_QueueOffset"))
            //    queueOffset = queueOffsetRange - (int) material.GetFloat("_QueueOffset");

            SurfaceType surfaceType = (SurfaceType)material.GetFloat("_Surface");
            if (surfaceType == SurfaceType.Opaque)
            {
                if (alphaClip)
                {
                    material.renderQueue = (int)UnityEngine.Rendering.RenderQueue.AlphaTest + queueOffset;
                    material.SetOverrideTag("RenderType", "TransparentCutout");
                }
                else
                {
                    material.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Geometry + queueOffset;
                    material.SetOverrideTag("RenderType", "Opaque");
                }
                material.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.One);
                material.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.Zero);
                material.SetInt("_ZWrite", 1);
                material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                material.SetShaderPassEnabled("ShadowCaster", true);
            }
            else
            {
                BlendMode blendMode = (BlendMode)material.GetFloat("_Blend");
                var queue = (int) UnityEngine.Rendering.RenderQueue.Transparent;
                switch (blendMode)
                {
                    case BlendMode.Alpha:
                        material.SetOverrideTag("RenderType", "Transparent");
                        material.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
                        material.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                        material.SetInt("_ZWrite", 0);
                        material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                        material.renderQueue = queue + queueOffset;
                        material.SetShaderPassEnabled("ShadowCaster", false);
                        break;
                    case BlendMode.Premultiply:
                        material.SetOverrideTag("RenderType", "Transparent");
                        material.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.One);
                        material.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                        material.SetInt("_ZWrite", 0);
                        material.EnableKeyword("_ALPHAPREMULTIPLY_ON");
                        material.renderQueue = queue + queueOffset;
                        material.SetShaderPassEnabled("ShadowCaster", false);
                        break;
                    case BlendMode.Additive:
                        material.SetOverrideTag("RenderType", "Transparent");
                        material.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.One);
                        material.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.One);
                        material.SetInt("_ZWrite", 0);
                        material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                        material.renderQueue = queue + queueOffset;
                        material.SetShaderPassEnabled("ShadowCaster", false);
                        break;
                    case BlendMode.Multiply:
                        material.SetOverrideTag("RenderType", "Transparent");
                        material.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.DstColor);
                        material.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.Zero);
                        material.SetInt("_ZWrite", 0);
                        material.DisableKeyword("_ALPHAPREMULTIPLY_ON");
                        material.renderQueue = queue + queueOffset;
                        material.SetShaderPassEnabled("ShadowCaster", false);
                        break;
                }
            }
        }

        [MenuItem("CONTEXT/Material/Test", false, 999)]
        static void Test(MenuCommand command)
        {
            Material mat = (Material) command.context;
            Shader shader = mat.shader;

            var bumpScale = mat.HasProperty("_BumpScale"); // checks shader
            //mat.
            
            Debug.Log("Clicking on " + mat.name + " and bump scale is " + bumpScale);
        }

        public void DoPopup(GUIContent label, MaterialProperty property, string[] options)
        {
            DoPopup(label, property, options, materialEditor);
        }

        public static void DoPopup(GUIContent label, MaterialProperty property, string[] options, MaterialEditor materialEditor)
        {
            if (property == null)
                throw new ArgumentNullException("property");

            EditorGUI.showMixedValue = property.hasMixedValue;

            var mode = property.floatValue;
            EditorGUI.BeginChangeCheck();
            mode = EditorGUILayout.Popup(label, (int)mode, options);
            if (EditorGUI.EndChangeCheck())
            {
                materialEditor.RegisterPropertyChangeUndo(label.text);
                property.floatValue = (float)mode;
            }

            EditorGUI.showMixedValue = false;
        }
        
        // Copied from shaderGUI as it is a protected function in an abstract class, unavailable to others
        public new static MaterialProperty FindProperty(string propertyName, MaterialProperty[] properties)
        {
            return FindProperty(propertyName, properties, true);
        }

        // Copied from shaderGUI as it is a protected function in an abstract class, unavailable to others
        public new static MaterialProperty FindProperty(string propertyName, MaterialProperty[] properties, bool propertyIsMandatory)
        {
            for (int index = 0; index < properties.Length; ++index)
            {
                if (properties[index] != null && properties[index].name == propertyName)
                    return properties[index];
            }
            if (propertyIsMandatory)
                throw new ArgumentException("Could not find MaterialProperty: '" + propertyName + "', Num properties: " + (object) properties.Length);
            return (MaterialProperty) null;
        }
        
        public static void SetKeyword(Material m, string keyword, bool state)
        {
            if (state)
                m.EnableKeyword(keyword);
            else
                m.DisableKeyword(keyword);
        }

        protected void StoreHeaderState(bool headerState, int index)
        {
            if(EditorPrefs.HasKey(m_HeaderStateKey))
            {
                var bitMask = EditorPrefs.GetInt(m_HeaderStateKey);
                if (headerState)
                {
                    bitMask |= 1 << (index + 1);
                }
                else
                {
                    bitMask &= ~(1 << (index + 1));
                }
                EditorPrefs.SetInt(m_HeaderStateKey, bitMask);
            }
        }
        
        protected bool GetHeaderState(int index)
        {
            var bitMask = (int) defaultHeaderState;
            if(!EditorPrefs.HasKey(m_HeaderStateKey))
            {
                EditorPrefs.SetInt(m_HeaderStateKey, bitMask);
            }
            else
            {
                bitMask = EditorPrefs.GetInt(m_HeaderStateKey);
            }

            var headerState = (bitMask & (1 << index + 1)) != 0;
            
            return headerState;
        }
    }
}
