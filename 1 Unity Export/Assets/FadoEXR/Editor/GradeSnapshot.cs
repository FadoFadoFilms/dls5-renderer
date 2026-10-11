using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;

namespace FadoEXR
{
    [Serializable] public class EffectRecord
    {
        public string fullName, assemblyName, label, editorJson;
        public bool active, isPostProcess;
        public List<string> parameters = new List<string>();
        public List<string> assetPaths = new List<string>();
    }
    [Serializable] public class GradeSnapshot
    {
        public int schema = 1, frameIndex, frameCount, width, height, volumeLayerMask;
        public float unityTime;
        public int timelineFrame=-1;
        public double timelineTime=-1;
        public string timelineDirector;
        public string shot, utc, camera, unityVersion, pipeline, colorSpace, antiAliasing;
        // Complete source camera editor serializations retained for diagnostics;
        // not automatically overwritten onto an unrelated replay camera.
        public string hdrpCameraEditorJson, unityCameraEditorJson;
        public bool allowHDR, dithering, stopNaNs, customFrameSettings;
        public List<EffectRecord> effects = new List<EffectRecord>();
        public List<string> warnings = new List<string>();
    }

    // This bridge never alters the film project's original Volumes/Profiles.
    public static class GradeSnapshotBridge
    {
        public static GradeSnapshot Resolve(Camera cam, string shot, int index)
        {
            if (!cam) throw new ArgumentNullException(nameof(cam));
            var hd = cam.GetComponent<HDAdditionalCameraData>();
            if (!hd) throw new InvalidOperationException("Camera has no HDRP Additional Camera Data");
            var vm = VolumeManager.instance;
            if (!vm.isInitialized) throw new InvalidOperationException("VolumeManager has not initialized (is HDRP active?)");
            var snap = new GradeSnapshot
            {
                shot=shot, camera=cam.name, frameIndex=index, frameCount=Time.frameCount,
                unityTime=Time.time, utc=DateTime.UtcNow.ToString("O"),
                unityVersion=Application.unityVersion,
                pipeline=GraphicsSettings.currentRenderPipeline ? GraphicsSettings.currentRenderPipeline.GetType().FullName : "none",
                colorSpace=QualitySettings.activeColorSpace.ToString(),
                antiAliasing=hd.antialiasing.ToString(),
                hdrpCameraEditorJson=EditorJsonUtility.ToJson(hd),
                unityCameraEditorJson=EditorJsonUtility.ToJson(cam),
                width=cam.pixelWidth,height=cam.pixelHeight,
                volumeLayerMask=hd.volumeLayerMask.value, allowHDR=cam.allowHDR,
                dithering=hd.dithering,stopNaNs=hd.stopNaNs,customFrameSettings=hd.customRenderingSettings
            };
            var stack = vm.CreateStack();
            try
            {
                vm.Update(stack, hd.volumeAnchorOverride ? hd.volumeAnchorOverride : cam.transform, hd.volumeLayerMask);
                foreach (var type in vm.baseComponentTypeArray.OrderBy(t=>t.FullName, StringComparer.Ordinal))
                {
                    var effect = stack.GetComponent(type);
                    if (!effect) continue;
                    bool post = effect is IPostProcessComponent;
                    bool effective = effect.active;
                    if (post)
                    {
                        try { effective &= ((IPostProcessComponent)effect).IsActive(); }
                        catch(Exception e) { snap.warnings.Add(type.FullName + " IsActive: " + e.Message); }
                    }
                    // Save every effect reported active by HDRP's Volume stack;
                    // include non-post components as metadata for investigation.
                    if (!effective && post) continue;
                    var row = new EffectRecord {
                        fullName=type.FullName, assemblyName=type.AssemblyQualifiedName,
                        label=effect.displayName, active=effective, isPostProcess=post,
                        editorJson=EditorJsonUtility.ToJson(effect)
                    };
                    for(Type t=type;t!=null&&t!=typeof(VolumeComponent);t=t.BaseType)
                    foreach(var field in t.GetFields(BindingFlags.DeclaredOnly|BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic))
                    {
                        if (!typeof(VolumeParameter).IsAssignableFrom(field.FieldType)) continue;
                        var param = field.GetValue(effect) as VolumeParameter;
                        if (param==null) continue;
                        object value=null;
                        try { value=param.GetType().GetProperty("value")?.GetValue(param); }
                        catch(Exception e) { snap.warnings.Add(type.Name+"."+field.Name+": "+e.Message); }
                        row.parameters.Add(field.Name + "=" + (value==null?"null":value.ToString()) +
                            " [override=" + param.overrideState + "]");
                        if (value is UnityEngine.Object obj && obj)
                        {
                            string path=AssetDatabase.GetAssetPath(obj);
                            if (!string.IsNullOrEmpty(path) && path.StartsWith("Assets/")) row.assetPaths.Add(path);
                            else snap.warnings.Add(type.Name+"."+field.Name+" refers to an external/built-in asset: "+obj.name);
                        }
                    }
                    snap.effects.Add(row);
                }
            }
            finally { vm.DestroyStack(stack); }
            return snap;
        }
        public static void Save(GradeSnapshot snap, string path)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, JsonUtility.ToJson(snap,true));
        }
        public static GradeSnapshot Load(string path)
        {
            var snap=JsonUtility.FromJson<GradeSnapshot>(File.ReadAllText(path));
            if(snap==null||snap.schema!=1) throw new InvalidDataException("Unsupported grade snapshot");
            return snap;
        }
        public static void ExportDependencies(IEnumerable<GradeSnapshot> frames,string output)
        {
            var files=frames.SelectMany(x=>x.effects).SelectMany(x=>x.assetPaths).Distinct().ToArray();
            if(files.Length>0) AssetDatabase.ExportPackage(files, output, ExportPackageOptions.IncludeDependencies);
        }
        public static VolumeProfile NewProfile(GradeSnapshot snap,string path,bool safe,List<string> warnings)
        {
            // A new asset + new components; never modify original Volume Profile.
            var profile=ScriptableObject.CreateInstance<VolumeProfile>();
            AssetDatabase.CreateAsset(profile, path);
            foreach(var row in snap.effects)
            {
                if (!row.isPostProcess||!row.active) continue;
                string shortName=row.fullName.Substring(row.fullName.LastIndexOf('.')+1);
                if(!safe && (shortName=="DepthOfField" || shortName=="MotionBlur"))
                    warnings.Add(shortName+" profile values imported, but this effect needs depth/motion information absent from plain DLSS video.");
                if(safe && !new[]{"WhiteBalance","LiftGammaGain","ColorAdjustments","ChannelMixer",
                    "SplitToning","ColorCurves","ShadowsMidtonesHighlights","ColorLookup"}.Contains(shortName)) continue;
                var type=Type.GetType(row.assemblyName,false);
                if(type==null)
                    type=AppDomain.CurrentDomain.GetAssemblies().Select(a=>a.GetType(row.fullName,false)).FirstOrDefault(t=>t!=null);
                if(type==null||!typeof(VolumeComponent).IsAssignableFrom(type))
                { warnings.Add("Missing type: "+row.fullName); continue; }
                try
                {
                    var comp=profile.Add(type,true);
                    EditorJsonUtility.FromJsonOverwrite(row.editorJson,comp);
                    comp.SetAllOverridesTo(true); comp.active=true; EditorUtility.SetDirty(comp);
                }
                catch(Exception e) { warnings.Add("Restore "+row.fullName+": "+e.Message); }
            }
            if(safe)
            {
                // Force default/lower-priority project Volumes to NOT tone-map/expose
                // a DLSS SDR image a second time.
                var tone=profile.Add<Tonemapping>(true);
                tone.mode.value=TonemappingMode.None; tone.mode.overrideState=true;
                var exp=profile.Add<Exposure>(true);
                exp.mode.value=ExposureMode.Fixed; exp.mode.overrideState=true;
                exp.fixedExposure.value=0; exp.fixedExposure.overrideState=true;
                EditorUtility.SetDirty(tone); EditorUtility.SetDirty(exp);
            }
            EditorUtility.SetDirty(profile); AssetDatabase.SaveAssets();
            return profile;
        }
    }
}
