using System;
using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Playables;

namespace FadoEXR
{
    public sealed class FilmCaptureWindow : EditorWindow
    {
        Camera camera;
        PlayableDirector director;
        int startFrame=0;
        bool accumulatorOffConfirmed;
        string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"FadoEXR_TestShots");
        string shot="Scene23_Shot04_TestA";
        int frames=1,fps=24;
        [MenuItem("Tools/Fado Fado/EXR Roundtrip/1 - Capture film")]
        static void ShowWindow(){GetWindow<FilmCaptureWindow>("FadoEXR Capture");}
        void OnInspectorUpdate(){Repaint();}
        void OnGUI()
        {
            EditorGUILayout.LabelField("Film camera -> paired EXR and Volume snapshot",EditorStyles.boldLabel);
            EditorGUILayout.HelpBox("Captures BEFORE postprocessing (Clean) and AFTER postprocessing (Reference), without changing your source Volume Profiles. Turn off Recorder frame blending/accumulation manually for the DLSS test. Enter Play Mode.",MessageType.Info);
            camera=(Camera)EditorGUILayout.ObjectField("Camera",camera,typeof(Camera),true);
            director=(PlayableDirector)EditorGUILayout.ObjectField("Optional Timeline director",director,typeof(PlayableDirector),true);
            if(director)startFrame=EditorGUILayout.IntField("Timeline start frame",startFrame);
            accumulatorOffConfirmed=EditorGUILayout.ToggleLeft("Recorder frame accumulation/blending and motion blur are OFF",accumulatorOffConfirmed);
            shot=EditorGUILayout.TextField("Unique shot ID",shot);
            frames=EditorGUILayout.IntSlider("Frames (1 for first test)",frames,1,240);
            fps=EditorGUILayout.IntSlider("Capture FPS",fps,1,60);
            EditorGUILayout.BeginHorizontal();
            root=EditorGUILayout.TextField("Output root",root);
            if(GUILayout.Button("Browse",GUILayout.Width(70)))
            {var p=EditorUtility.OpenFolderPanel("Capture output",root,"");if(!string.IsNullOrEmpty(p))root=p;}
            EditorGUILayout.EndHorizontal();
            GUI.enabled=EditorApplication.isPlaying&&!FilmCapture.Active&&camera&&(frames==1||accumulatorOffConfirmed);
            if(GUILayout.Button("Capture clean + reference + all resolved effects",GUILayout.Height(34)))
            {try{FilmCapture.Start(camera,root,shot,frames,fps,director,startFrame);}catch(Exception e){EditorUtility.DisplayDialog("Capture error",e.Message,"OK");}}
            GUI.enabled=FilmCapture.Active;
            if(GUILayout.Button("Cancel capture"))FilmCapture.Stop("Canceled by user");
            GUI.enabled=true;
            EditorGUILayout.HelpBox(FilmCapture.Status,MessageType.None);
            EditorGUILayout.HelpBox("If Timeline is assigned, the tool samples startFrame+i at the specified FPS in LateUpdate. Cinemachine/external procedural scripts can still need validation. Capture a 1-frame test first.",MessageType.Warning);
        }
    }
}
