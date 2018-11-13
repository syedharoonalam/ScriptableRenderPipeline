using System;
using System.Linq;
using System.Globalization;
using UnityEditor.Experimental.UIElements;
using UnityEditor.Experimental.UIElements.GraphView;
using UnityEditor.Graphing;
using UnityEditor.Graphing.Util;
using UnityEngine;
using UnityEngine.Experimental.UIElements;
using UnityEngine.Experimental.UIElements.StyleSheets;
using Toggle = UnityEngine.Experimental.UIElements.Toggle;
#if UNITY_2018_3_OR_NEWER
using ContextualMenu = UnityEngine.Experimental.UIElements.DropdownMenu;
#endif

namespace UnityEditor.ShaderGraph.Drawing
{
    class BlackboardFieldPropertyView : VisualElement
    {
        readonly BlackboardField m_BlackboardField;
        readonly AbstractMaterialGraph m_Graph;

        IShaderProperty m_Property;
        Toggle m_ExposedToogle;
        TextField m_ReferenceNameField;

        static Type s_ContextualMenuManipulator = AppDomain.CurrentDomain.GetAssemblies().SelectMany(x => x.GetTypesOrNothing()).FirstOrDefault(t => t.FullName == "UnityEngine.Experimental.UIElements.ContextualMenuManipulator");

        IManipulator m_ResetReferenceMenu;

        public delegate void OnExposedToggle();
        private OnExposedToggle m_OnExposedToggle;
        
        public BlackboardFieldPropertyView(BlackboardField blackboardField, AbstractMaterialGraph graph, IShaderProperty property)
        {
            AddStyleSheetPath("Styles/ShaderGraphBlackboard");
            m_BlackboardField = blackboardField;
            m_Graph = graph;
            m_Property = property;

            m_ExposedToogle = new Toggle();
            m_ExposedToogle.OnToggleChanged(evt =>
            {
                m_Graph.owner.RegisterCompleteObjectUndo("Change Exposed Toggle");
                if(m_OnExposedToggle != null)
                    m_OnExposedToggle();
                property.generatePropertyBlock = evt.newValue;
                if (property.generatePropertyBlock)
                {
                    m_BlackboardField.icon = BlackboardProvider.exposedIcon;
                }
                else
                {
                    m_BlackboardField.icon = null;
                }
                DirtyNodes(ModificationScope.Graph);
            });
            m_ExposedToogle.value = property.generatePropertyBlock;
            AddRow("Exposed", m_ExposedToogle);

            m_ReferenceNameField = new TextField(512, false, false, ' ');
            m_ReferenceNameField.AddStyleSheetPath("Styles/PropertyNameReferenceField");
            AddRow("Reference", m_ReferenceNameField);
            m_ReferenceNameField.value = property.referenceName;
            m_ReferenceNameField.isDelayed = true;
            m_ReferenceNameField.OnValueChanged(newName =>
                {
                    m_Graph.owner.RegisterCompleteObjectUndo("Change reference name");
                    if (m_ReferenceNameField.value != m_Property.referenceName)
                    {
                        string newReferenceName = m_Graph.SanitizePropertyReferenceName(newName.newValue, property.guid);
                        property.overrideReferenceName = newReferenceName;
                    }
                    m_ReferenceNameField.value = property.referenceName;

                    if (string.IsNullOrEmpty(property.overrideReferenceName))
                        m_ReferenceNameField.RemoveFromClassList("modified");
                    else
                        m_ReferenceNameField.AddToClassList("modified");

                    DirtyNodes(ModificationScope.Graph);
                    UpdateReferenceNameResetMenu();
                });

            if (!string.IsNullOrEmpty(property.overrideReferenceName))
                m_ReferenceNameField.AddToClassList("modified");

            if (property is Vector1ShaderProperty)
            {
                var floatProperty = (Vector1ShaderProperty)property;
                BuildVector1PropertyView(floatProperty);
            }
            else if (property is Vector2ShaderProperty)
            {
                var vectorProperty = (Vector2ShaderProperty)property;
                var field = new Vector2Field { value = vectorProperty.value };
                field.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        vectorProperty.value = evt.newValue;
                        DirtyNodes();
                    });
                AddRow("Default", field);
            }
            else if (property is Vector3ShaderProperty)
            {
                var vectorProperty = (Vector3ShaderProperty)property;
                var field = new Vector3Field { value = vectorProperty.value };
                field.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        vectorProperty.value = evt.newValue;
                        DirtyNodes();
                    });
                AddRow("Default", field);
            }
            else if (property is Vector4ShaderProperty)
            {
                var vectorProperty = (Vector4ShaderProperty)property;
                var field = new Vector4Field { value = vectorProperty.value };
                field.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        vectorProperty.value = evt.newValue;
                        DirtyNodes();
                    });
                AddRow("Default", field);
            }
            else if (property is ColorShaderProperty)
            {
                var colorProperty = (ColorShaderProperty)property;
                var colorField = new ColorField { value = property.defaultValue, showEyeDropper = false, hdr = colorProperty.colorMode == ColorMode.HDR };
                colorField.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        colorProperty.value = evt.newValue;
                        DirtyNodes();
                    });
                AddRow("Default", colorField);
                var colorModeField = new EnumField((Enum)colorProperty.colorMode);
                colorModeField.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change Color Mode");
                        if (colorProperty.colorMode == (ColorMode)evt.newValue)
                            return;
                        colorProperty.colorMode = (ColorMode)evt.newValue;
                        colorField.hdr = colorProperty.colorMode == ColorMode.HDR;
                        colorField.MarkDirtyRepaint();
                        DirtyNodes();
                    });
                AddRow("Mode", colorModeField);
            }
            else if (property is TextureShaderProperty)
            {
                var textureProperty = (TextureShaderProperty)property;
                var field = new ObjectField { value = textureProperty.value.texture, objectType = typeof(Texture) };
                field.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        textureProperty.value.texture = (Texture)evt.newValue;
                        DirtyNodes();
                    });
                AddRow("Default", field);
                var defaultModeField = new EnumField((Enum)textureProperty.defaultType);
                defaultModeField.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change Texture Mode");
                        if (textureProperty.defaultType == (TextureShaderProperty.DefaultType)evt.newValue)
                            return;
                        textureProperty.defaultType = (TextureShaderProperty.DefaultType)evt.newValue;
                        DirtyNodes(ModificationScope.Graph);
                    });
                void ToggleDefaultModeFieldEnabled()
                {
                    defaultModeField.SetEnabled(!defaultModeField.enabledSelf);
                }
                m_OnExposedToggle += toggleDefaultModeFieldEnabled;
                AddRow("Mode", defaultModeField);
            }
            else if (property is Texture2DArrayShaderProperty)
            {
                var textureProperty = (Texture2DArrayShaderProperty)property;
                var field = new ObjectField { value = textureProperty.value.textureArray, objectType = typeof(Texture2DArray) };
                field.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        textureProperty.value.textureArray = (Texture2DArray)evt.newValue;
                        DirtyNodes();
                    });
                AddRow("Default", field);
            }
            else if (property is Texture3DShaderProperty)
            {
                var textureProperty = (Texture3DShaderProperty)property;
                var field = new ObjectField { value = textureProperty.value.texture, objectType = typeof(Texture3D) };
                field.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        textureProperty.value.texture = (Texture3D)evt.newValue;
                        DirtyNodes();
                    });
                AddRow("Default", field);
            }
            else if (property is CubemapShaderProperty)
            {
                var cubemapProperty = (CubemapShaderProperty)property;
                var field = new ObjectField { value = cubemapProperty.value.cubemap, objectType = typeof(Cubemap) };
                field.OnValueChanged(evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        cubemapProperty.value.cubemap = (Cubemap)evt.newValue;
                        DirtyNodes();
                    });
                AddRow("Default", field);
            }
            else if (property is BooleanShaderProperty)
            {
                var booleanProperty = (BooleanShaderProperty)property;
                EventCallback<ChangeEvent<bool>> onBooleanChanged = evt =>
                    {
                        m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                        booleanProperty.value = evt.newValue;
                        DirtyNodes();
                    };
                var field = new Toggle();
                field.OnToggleChanged(onBooleanChanged);
                field.value = booleanProperty.value;
                AddRow("Default", field);
            }
//            AddRow("Type", new TextField());
//            AddRow("Exposed", new Toggle(null));
//            AddRow("Range", new Toggle(null));
//            AddRow("Default", new TextField());
//            AddRow("Tooltip", new TextField());


            AddToClassList("sgblackboardFieldPropertyView");

            UpdateReferenceNameResetMenu();
        }

        void BuildVector1PropertyView(Vector1ShaderProperty floatProperty)
        {
            VisualElement[] rows = null;

            switch (floatProperty.floatType)
            {
                case FloatType.Slider:
                    {
                        float min = Mathf.Min(floatProperty.value, floatProperty.rangeValues.x);
                        float max = Mathf.Max(floatProperty.value, floatProperty.rangeValues.y);
                        floatProperty.rangeValues = new Vector2(min, max);

                        var defaultField = new FloatField { value = floatProperty.value };
                        var minField = new FloatField { value = floatProperty.rangeValues.x };
                        var maxField = new FloatField { value = floatProperty.rangeValues.y };

                        defaultField.OnValueChanged(evt =>
                        {
                            var value = (float)evt.newValue;
                            floatProperty.value = value;
                            this.MarkDirtyRepaint();
                        });
                        defaultField.RegisterCallback<FocusOutEvent>(evt =>
                        {
                            m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                            float minValue = Mathf.Min(floatProperty.value, floatProperty.rangeValues.x);
                            float maxValue = Mathf.Max(floatProperty.value, floatProperty.rangeValues.y);
                            floatProperty.rangeValues = new Vector2(minValue, maxValue);
                            minField.value = minValue;
                            maxField.value = maxValue;
                            DirtyNodes();
                        });
                        minField.RegisterCallback<InputEvent>(evt =>
                        {
                            m_Graph.owner.RegisterCompleteObjectUndo("Change Range property minimum");
                            float newValue;
                            if (!float.TryParse(evt.newData, NumberStyles.Float, CultureInfo.InvariantCulture.NumberFormat, out newValue))
                                newValue = 0f;

                            floatProperty.rangeValues = new Vector2(newValue, floatProperty.rangeValues.y);
                            DirtyNodes();
                        });
                        minField.RegisterCallback<FocusOutEvent>(evt =>
                        {
                            floatProperty.value = Mathf.Max(Mathf.Min(floatProperty.value, floatProperty.rangeValues.y), floatProperty.rangeValues.x);
                            defaultField.value = floatProperty.value;
                            DirtyNodes();
                        });
                        maxField.RegisterCallback<InputEvent>(evt =>
                        {
                            m_Graph.owner.RegisterCompleteObjectUndo("Change Range property maximum");
                            float newValue;
                            if (!float.TryParse(evt.newData, NumberStyles.Float, CultureInfo.InvariantCulture.NumberFormat, out newValue))
                                newValue = 0f;

                            floatProperty.rangeValues = new Vector2(floatProperty.rangeValues.x, newValue);
                            DirtyNodes();
                        });
                        maxField.RegisterCallback<FocusOutEvent>(evt =>
                        {
                            floatProperty.value = Mathf.Max(Mathf.Min(floatProperty.value, floatProperty.rangeValues.y), floatProperty.rangeValues.x);
                            defaultField.value = floatProperty.value;
                            DirtyNodes();
                        });
                        rows = new VisualElement[4];
                        rows[0] = CreateRow("Default", defaultField);
                        rows[2] = CreateRow("Min", minField);
                        rows[3] = CreateRow("Max", maxField);
                    }
                    break;
                case FloatType.Integer:
                    {
                        floatProperty.value = (int)floatProperty.value;
                        var defaultField = new IntegerField { value = (int)floatProperty.value };
                        defaultField.OnValueChanged(evt =>
                        {
                            m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                            var value = (int)evt.newValue;
                            floatProperty.value = value;
                            this.MarkDirtyRepaint();
                        });
                        rows = new VisualElement[2];
                        rows[0] = CreateRow("Default", defaultField);
                    }
                    break;
                default:
                    {
                        var defaultField = new FloatField { value = floatProperty.value };
                        defaultField.OnValueChanged(evt =>
                        {
                            m_Graph.owner.RegisterCompleteObjectUndo("Change property value");
                            var value = (float)evt.newValue;
                            floatProperty.value = value;
                            this.MarkDirtyRepaint();
                        });
                        rows = new VisualElement[2];
                        rows[0] = CreateRow("Default", defaultField);
                    }
                    break;
            }

            var modeField = new EnumField(floatProperty.floatType);
            modeField.OnValueChanged(evt =>
            {
                m_Graph.owner.RegisterCompleteObjectUndo("Change Vector1 mode");
                var value = (FloatType)evt.newValue;
                floatProperty.floatType = value;
                if (rows != null)
                    RemoveElements(rows);
                BuildVector1PropertyView(floatProperty);
                this.MarkDirtyRepaint();
            });
            rows[1] = CreateRow("Mode", modeField);

            if (rows == null)
                return;

            for (int i = 0; i < rows.Length; i++)
                Add(rows[i]);
        }

        void UpdateReferenceNameResetMenu()
        {
            if (string.IsNullOrEmpty(m_Property.overrideReferenceName))
            {
                this.RemoveManipulator(m_ResetReferenceMenu);
                m_ResetReferenceMenu = null;
            }
            else
            {
                m_ResetReferenceMenu = (IManipulator)Activator.CreateInstance(s_ContextualMenuManipulator, (Action<ContextualMenuPopulateEvent>)BuildContextualMenu);
                this.AddManipulator(m_ResetReferenceMenu);
            }
        }

        void BuildContextualMenu(ContextualMenuPopulateEvent evt)
        {
            evt.menu.AppendAction("Reset reference", e =>
                {
                    m_Property.overrideReferenceName = null;
                    m_ReferenceNameField.value = m_Property.referenceName;
                    m_ReferenceNameField.RemoveFromClassList("modified");
                    DirtyNodes(ModificationScope.Graph);
                }, ContextualMenu.MenuAction.AlwaysEnabled);
        }

        VisualElement CreateRow(string labelText, VisualElement control)
        {
            VisualElement rowView = new VisualElement();

            rowView.AddToClassList("rowView");

            Label label = new Label(labelText);

            label.AddToClassList("rowViewLabel");
            rowView.Add(label);

            control.AddToClassList("rowViewControl");
            rowView.Add(control);

            return rowView;
        }

        VisualElement AddRow(string labelText, VisualElement control)
        {
            VisualElement rowView = CreateRow(labelText, control);
            Add(rowView);
            return rowView;
        }

        void RemoveElements(VisualElement[] elements)
        {
            for (int i = 0; i < elements.Length; i++)
            {
                if (elements[i].parent == this)
                    Remove(elements[i]);
            }
        }

        void DirtyNodes(ModificationScope modificationScope = ModificationScope.Node)
        {
            foreach (var node in m_Graph.GetNodes<PropertyNode>())
                node.Dirty(modificationScope);
        }
    }
}
