using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;

namespace FadoEXR
{
    public sealed class ReplayWindow : EditorWindow
    {
        Camera camera;
        GradeSnapshot grade;
        List<GradeSnapshot> grades=new List<GradeSnapshot>();
        string gradePath="";
        Volume restoredVolume;
        VolumeProfile safeProfile,fullProfile;
        List<VolumeProfile> safeProfiles=new List<VolumeProfile>(),fullProfiles=new List<VolumeProfile>();
        bool reuseStaticGrade=false;
        List<Texture2D> frames=new List<Texture2D>();
        string output=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"FadoEXR_Regraded");
        bool safe=true,flipY=false;
        int fps=24;
        string status="Choose a saved grade snapshot and frames from the DLSS output.";
        Vector2 scroll;

        [MenuItem("Tools/Fado Fado/EXR Roundtrip/2 - Restore in EXR Renderer")]
        static void ShowWindow(){GetWindow<ReplayWindow>("EXR Renderer");}
        void OnInspectorUpdate(){Repaint();}
        void OnGUI()
        {
            scroll=EditorGUILayout.BeginScrollView(scroll);
            GUILayout.Label("EXR Renderer / DLSS colour round-trip",EditorStyles.boldLabel);
            EditorGUILayout.HelpBox("Use a separate blank Unity 6 HDRP project. FULL reconstructs every available active HDRP post effect; SAFE replays colour controls only and overrides Tonemapping/Exposure to avoid a second conversion of SDR DLSS output.",MessageType.Info);
            camera=(Camera)EditorGUILayout.ObjectField("Replay camera",camera,typeof(Camera),true);
            if(GUILayout.Button("Create replay camera"))CreateCamera();
            EditorGUILayout.Space();
            GUILayout.Label("1. Import recorded post-processing",EditorStyles.boldLabel);
            if(GUILayout.Button("Load grade_000000.json"))
            {
                string p=EditorUtility.OpenFilePanel("Camera grade JSON", "", "json");
                if(!string.IsNullOrEmpty(p))
                {
                    try{grade=GradeSnapshotBridge.Load(p);gradePath=p;
                        grades=new List<GradeSnapshot>{grade};
                        safeProfiles.Clear();fullProfiles.Clear();
                        status="Loaded ONE grade. Load a Grade folder to restore animated values.";}
                    catch(Exception e){EditorUtility.DisplayDialog("Grade error",e.Message,"OK");}
                }
            }
            if(GUILayout.Button("Load per-frame Grade FOLDER"))LoadGradeFolder();
            EditorGUILayout.LabelField("Recorded grade frames",grades.Count.ToString());
            if(grade!=null)
            {
                EditorGUILayout.LabelField("Source camera",grade.camera);
                EditorGUILayout.LabelField("Unity version",grade.unityVersion);
                foreach(var e in grade.effects.Where(e=>e.isPostProcess&&e.active))
                    EditorGUILayout.LabelField("- "+e.fullName.Substring(e.fullName.LastIndexOf('.')+1),EditorStyles.miniLabel);
            }
            if(GUILayout.Button("Import referenced-assets.unitypackage (if present)"))
            {
                var p=EditorUtility.OpenFilePanel("Shot referenced Unity assets", "", "unitypackage");
                if(!string.IsNullOrEmpty(p))AssetDatabase.ImportPackage(p,true);
            }
            safe=EditorGUILayout.ToggleLeft("Use SAFE colour-only profile for SDR DLSS (recommended)",safe);
            GUI.enabled=grade!=null;
            if(GUILayout.Button("Create FULL + SAFE Volume profiles",GUILayout.Height(30)))CreateProfiles();
            GUI.enabled=true;
            if(restoredVolume)
            {
                if(GUILayout.Button("Apply selected profile to new Volume"))
                    restoredVolume.sharedProfile=safe?safeProfile:fullProfile;
                EditorGUILayout.LabelField("Current Volume",restoredVolume.sharedProfile?restoredVolume.sharedProfile.name:"none");
            }
            EditorGUILayout.Space();
            GUILayout.Label("2. Import DLSS-exported image sequence",EditorStyles.boldLabel);
            EditorGUILayout.HelpBox("Convert the DLSS player's exported lossless video to PNG frames with Tools/Video-To-PNG16.cmd. Then import the PNG folder. EXR also supported. This copies files into the NEW Unity project, never modifies the originals.",MessageType.None);
            if(GUILayout.Button("Import PNG / EXR frames"))ImportFrames();
            EditorGUILayout.LabelField("Imported frames",frames.Count.ToString());
            if(grades.Count==1&&frames.Count>1)
                reuseStaticGrade=EditorGUILayout.ToggleLeft("I confirm this shot has STATIC grading; reuse one grade on all frames",reuseStaticGrade);
            if(grades.Count>1&&frames.Count>0&&grades.Count!=frames.Count)
                EditorGUILayout.HelpBox("Grade count must exactly match input frames.",MessageType.Error);
            flipY=EditorGUILayout.ToggleLeft("Flip vertically if necessary",flipY);
            fps=EditorGUILayout.IntSlider("FPS for short test",fps,1,60);
            EditorGUILayout.BeginHorizontal();
            output=EditorGUILayout.TextField("Output EXRs",output);
            if(GUILayout.Button("Browse",GUILayout.Width(70)))
            {var p=EditorUtility.OpenFolderPanel("Output EXRs",output,"");if(!string.IsNullOrEmpty(p))output=p;}
            EditorGUILayout.EndHorizontal();
            GUI.enabled=EditorApplication.isPlaying&&camera&&restoredVolume&&frames.Count>0&&!ReplayRunner.Active&&
                (grades.Count==frames.Count||(grades.Count==1&&reuseStaticGrade))&&
                (safe?safeProfiles.Count:fullProfiles.Count)==grades.Count;
            if(GUILayout.Button("Render regraded EXR sequence",GUILayout.Height(34)))
            {
                try{restoredVolume.sharedProfile=safe?safeProfile:fullProfile;
                    var list=safe?safeProfiles:fullProfiles;
                    var perFrame=new List<VolumeProfile>();
                    for(int i=0;i<frames.Count;i++)perFrame.Add(list.Count==1?list[0]:list[i]);
                    ReplayRunner.Start(camera,frames,restoredVolume,perFrame,output,fps,flipY);}
                catch(Exception e){EditorUtility.DisplayDialog("Replay error",e.Message,"OK");}
            }
            GUI.enabled=ReplayRunner.Active;
            if(GUILayout.Button("Stop replay"))ReplayRunner.Stop("Canceled by user");
            GUI.enabled=true;
            EditorGUILayout.HelpBox("V0.2 matches a saved Volume Profile to each image by frame index when you load a Grade folder. Some effects require depth/motion buffers, and a DLSS SDR output is not interchangeable with scene-linear HDR.",MessageType.Warning);
            EditorGUILayout.HelpBox(status+"\n"+ReplayRunner.Status,MessageType.None);
            EditorGUILayout.EndScrollView();
        }
        void LoadGradeFolder()
        {
            var folder=EditorUtility.OpenFolderPanel("Captured Grade folder","","");
            if(string.IsNullOrEmpty(folder))return;
            try
            {
                var files=Directory.GetFiles(folder,"grade_*.json")
                    .OrderBy(x=>Path.GetFileName(x),StringComparer.OrdinalIgnoreCase).ToArray();
                if(files.Length<1||files.Length>240)throw new IOException("Choose 1-240 grade_XXXXXX.json files");
                var loaded=files.Select(GradeSnapshotBridge.Load).ToList();
                for(int i=0;i<loaded.Count;i++)
                    if(loaded[i].frameIndex!=i)throw new IOException("Missing grade frame "+i);
                grades=loaded;grade=loaded[0];gradePath=files[0];
                safeProfiles.Clear();fullProfiles.Clear();reuseStaticGrade=false;
                status="Loaded "+loaded.Count+" distinct frame grades.";
            }
            catch(Exception e){EditorUtility.DisplayDialog("Load Grades error",e.ToString(),"OK");}
        }
        void CreateCamera()
        {
            var go=new GameObject("FadoEXR Replay Camera");
            Undo.RegisterCreatedObjectUndo(go,"Create replay camera");
            camera=go.AddComponent<Camera>();
            camera.allowHDR=true;
            camera.clearFlags=CameraClearFlags.SolidColor;
            camera.backgroundColor=Color.black;
            go.AddComponent<HDAdditionalCameraData>();
            Selection.activeGameObject=go;
            status="Replay camera created; verify its Custom Pass and Post Processing Frame Settings.";
        }
        void CreateProfiles()
        {
            if(!camera)CreateCamera();
            try
            {
                if(!AssetDatabase.IsValidFolder("Assets/FadoEXRGenerated"))
                    AssetDatabase.CreateFolder("Assets","FadoEXRGenerated");
                string basename=Path.GetFileNameWithoutExtension(gradePath).Replace(" ","_");
                string full=AssetDatabase.GenerateUniqueAssetPath("Assets/FadoEXRGenerated/"+basename+"_FULL.asset");
                string col=AssetDatabase.GenerateUniqueAssetPath("Assets/FadoEXRGenerated/"+basename+"_SAFE.asset");
                var warnings=new List<string>();
                fullProfile=GradeSnapshotBridge.NewProfile(grade,full,false,warnings);
                safeProfile=GradeSnapshotBridge.NewProfile(grade,col,true,warnings);
                fullProfiles=new List<VolumeProfile>{fullProfile};
                safeProfiles=new List<VolumeProfile>{safeProfile};
                for(int i=1;i<grades.Count;i++)
                {
                    string tag="Assets/FadoEXRGenerated/Grade_"+DateTime.UtcNow.ToString("yyyyMMdd_HHmmss_fff")+"_"+i.ToString("D6");
                    fullProfiles.Add(GradeSnapshotBridge.NewProfile(grades[i],
                        AssetDatabase.GenerateUniqueAssetPath(tag+"_FULL.asset"),false,warnings));
                    safeProfiles.Add(GradeSnapshotBridge.NewProfile(grades[i],
                        AssetDatabase.GenerateUniqueAssetPath(tag+"_SAFE.asset"),true,warnings));
                }
                if(!restoredVolume)
                {
                    var go=new GameObject("FadoEXR Reconstructed Post Processing");
                    Undo.RegisterCreatedObjectUndo(go,"Create restored HDRP Volume");
                    restoredVolume=go.AddComponent<Volume>();
                    restoredVolume.isGlobal=true;
                    restoredVolume.priority=10000f;
                    go.layer=0;
                }
                restoredVolume.sharedProfile=safe?safeProfile:fullProfile;
                var hd=camera.GetComponent<HDAdditionalCameraData>();
                hd.volumeLayerMask=hd.volumeLayerMask.value|1;
                EditorUtility.SetDirty(restoredVolume);
                EditorUtility.SetDirty(hd);
                Selection.activeGameObject=restoredVolume.gameObject;
                status="New profiles created under Assets/FadoEXRGenerated. "+
                    (warnings.Count>0?"WARNINGS: "+string.Join(" | ",warnings):"All recorded effect types were found.");
            }
            catch(Exception e){EditorUtility.DisplayDialog("Volume reconstruction error",e.ToString(),"OK");}
        }
        void ImportFrames()
        {
            string path=EditorUtility.OpenFolderPanel("PNG / EXR frames from DLSS output","","");
            if(string.IsNullOrEmpty(path))return;
            try
            {
                var files=Directory.GetFiles(path).Where(f=>f.EndsWith(".png",StringComparison.OrdinalIgnoreCase)||
                        f.EndsWith(".exr",StringComparison.OrdinalIgnoreCase))
                    .OrderBy(f=>Path.GetFileName(f),StringComparer.OrdinalIgnoreCase).ToArray();
                if(files.Length<1||files.Length>240)throw new IOException("Choose 1-240 numbered PNG/EXR frames for the test.");
                if(!AssetDatabase.IsValidFolder("Assets/FadoEXRImported"))AssetDatabase.CreateFolder("Assets","FadoEXRImported");
                string stamp="Frames_"+DateTime.UtcNow.ToString("yyyyMMdd_HHmmss_fff");
                AssetDatabase.CreateFolder("Assets/FadoEXRImported",stamp);
                var list=new List<Texture2D>();
                foreach(string file in files)
                {
                    string dst="Assets/FadoEXRImported/"+stamp+"/"+Path.GetFileName(file);
                    File.Copy(file,Path.Combine(Directory.GetCurrentDirectory(),dst));
                    AssetDatabase.ImportAsset(dst,ImportAssetOptions.ForceSynchronousImport);
                    var importer=AssetImporter.GetAtPath(dst) as TextureImporter;
                    if(importer!=null)
                    {
                        importer.sRGBTexture=file.EndsWith(".png",StringComparison.OrdinalIgnoreCase);
                        importer.mipmapEnabled=false;
                        importer.textureCompression=TextureImporterCompression.Uncompressed;
                        importer.maxTextureSize=8192;
                        importer.npotScale=TextureImporterNPOTScale.None;
                        importer.SaveAndReimport();
                    }
                    var tex=AssetDatabase.LoadAssetAtPath<Texture2D>(dst);
                    if(!tex)throw new IOException("Cannot import: "+file);
                    // Keep a fixed short R&D shot under a conservative VRAM bound.
                    // Without streaming, retaining many 4K frames can exhaust a 6 GB card.
                    long bytes=(long)tex.width*tex.height*8L*files.Length;
                    if(bytes>700L*1024L*1024L)
                        throw new IOException("Sequence too large for conservative RTX 2060 prototype (~"+
                            (bytes/(1024*1024))+" MiB uncompressed). Choose fewer frames / 1080p. Files already copied remain under Assets/FadoEXRImported.");
                    list.Add(tex);
                }
                frames=list;
                status="Imported "+frames.Count+" input frames under Assets/FadoEXRImported.";
            }
            catch(Exception e){EditorUtility.DisplayDialog("Frame import problem",e.Message,"OK");}
        }
    }
}
