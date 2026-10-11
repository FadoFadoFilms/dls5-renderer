using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Playables;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;

namespace FadoEXR
{
    // Copy current camera buffer at two distinct HDRP injection points.
    public static class ExrGpuSaver
    {
        public static void Enqueue(CustomPassContext ctx,string path,Action<bool,string> callback)
        {
            int width=ctx.hdCamera.actualWidth, height=ctx.hdCamera.actualHeight;
            if(width<1||height<1) { callback(false,"Camera has no pixels"); return; }
            var rt=new RenderTexture(width,height,0,RenderTextureFormat.ARGBHalf,RenderTextureReadWrite.Linear);
            rt.antiAliasing=1; rt.useMipMap=false; rt.Create();
            var scale=RTHandles.rtHandleProperties.rtHandleScale;
            ctx.cmd.Blit(ctx.cameraColorBuffer,rt,new Vector2(scale.x,scale.y),Vector2.zero,0,0);
            // Must be CommandBuffer readback, not an immediate GPU read: copy is deferred.
            ctx.cmd.RequestAsyncReadback(rt,0,request=>
            {
                try
                {
                    if(request.hasError) throw new IOException("GPU readback failed");
                    byte[] pixels=request.GetData<byte>().ToArray();
                    if(pixels.Length!=width*height*8) throw new IOException("Unexpected ARGBHalf size: "+pixels.Length);
                    var tex=new Texture2D(width,height,TextureFormat.RGBAHalf,false,true);
                    try
                    {
                        tex.LoadRawTextureData(pixels); tex.Apply(false,false);
                        Directory.CreateDirectory(Path.GetDirectoryName(path));
                        File.WriteAllBytes(path,tex.EncodeToEXR(Texture2D.EXRFlags.CompressZIP));
                        callback(true,path);
                    }
                    finally { UnityEngine.Object.DestroyImmediate(tex); }
                }
                catch(Exception e) { callback(false,e.ToString()); }
                finally { rt.Release(); UnityEngine.Object.DestroyImmediate(rt); }
            });
        }
    }
    [Serializable] public sealed class CleanCapturePass : CustomPass
    {
        protected override void Execute(CustomPassContext ctx) { FilmCapture.OnPass(ctx,true); }
    }
    [Serializable] public sealed class ReferenceCapturePass : CustomPass
    {
        protected override void Execute(CustomPassContext ctx) { FilmCapture.OnPass(ctx,false); }
    }

    public static class FilmCapture
    {
        sealed class Job
        {
            public Camera camera; public string folder,shot;
            public int count,requested,readbacks,errors,oldFramerate,lastBefore=-1,lastAfter=-1,activeIndex=-1;
            public CleanCapturePass before; public ReferenceCapturePass after;
            public PlayableDirector director;
            public DirectorUpdateMode oldDirectorMode;
            public PlayState oldDirectorState;
            public double oldDirectorTime;
            public int fps,startFrame,preparedFrame=-1,preparedIndex=-1;
            public GameObject driverObject;
            public readonly List<GradeSnapshot> grades=new List<GradeSnapshot>();
            public readonly List<string> log=new List<string>();
        }
        static Job current;
        public static bool Active=>current!=null;
        public static string Status {get;private set;}="Ready";
        public static void Start(Camera camera,string root,string shot,int count,int fps,PlayableDirector timeline=null,int startFrame=0)
        {
            if(Active) throw new InvalidOperationException("Capture already running");
            if(!EditorApplication.isPlaying) throw new InvalidOperationException("Enter Play Mode first");
            if(!camera||!camera.GetComponent<HDAdditionalCameraData>()) throw new ArgumentException("Select your HDRP film camera");
            if(!(GraphicsSettings.currentRenderPipeline is HDRenderPipelineAsset)) throw new InvalidOperationException("HDRP is required");
            if(string.IsNullOrEmpty(root)) throw new ArgumentException("Choose an output folder");
            if(startFrame<0)throw new ArgumentException("Timeline start frame cannot be negative");
            if(timeline && !timeline.playableAsset)throw new ArgumentException("Timeline director has no playable asset");
            foreach(char ch in Path.GetInvalidFileNameChars()) shot=shot.Replace(ch,'_');
            string folder=Path.Combine(root,string.IsNullOrWhiteSpace(shot)?"TestShot":shot);
            if(Directory.Exists(folder)&&Directory.GetFileSystemEntries(folder).Length>0)
                throw new IOException("Output folder is not empty. Use a unique Shot ID; existing captures are preserved.");
            Directory.CreateDirectory(folder);
            current=new Job{camera=camera,folder=folder,shot=shot,count=Mathf.Clamp(count,1,240),
                oldFramerate=Time.captureFramerate,before=new CleanCapturePass(),after=new ReferenceCapturePass(),
                director=timeline,fps=fps,startFrame=startFrame};
            Time.captureFramerate=count>1?Mathf.Clamp(fps,1,120):current.oldFramerate;
            CustomPassVolume.RegisterGlobalCustomPass(CustomPassInjectionPoint.BeforePostProcess,current.before);
            CustomPassVolume.RegisterGlobalCustomPass(CustomPassInjectionPoint.AfterPostProcess,current.after);
            if(timeline)
            {
                var job=current;
                job.oldDirectorMode=timeline.timeUpdateMode;
                job.oldDirectorTime=timeline.time;
                job.oldDirectorState=timeline.state;
                if(timeline.state!=PlayState.Playing)timeline.Play();
                timeline.Pause();
                timeline.timeUpdateMode=DirectorUpdateMode.Manual;
                job.driverObject=new GameObject("FadoEXR Temporary Timeline Driver");
                job.driverObject.hideFlags=HideFlags.HideAndDontSave;
                var driver=job.driverObject.AddComponent<FadoFrameDriver>();
                driver.Next=()=>current==job&&job.requested<job.count?job.requested:-1;
                driver.Prepare=(unityFrame,index)=>
                {
                    if(current!=job)return;
                    timeline.time=(job.startFrame+index)/(double)job.fps;
                    timeline.Evaluate();
                    job.preparedFrame=unityFrame;
                    job.preparedIndex=index;
                };
            }
            EditorApplication.playModeStateChanged+=OnPlayMode;
            Status="Armed for "+current.count+" frame(s). Render selected Game camera.";
        }
        static void OnPlayMode(PlayModeStateChange state)
        {
            if(state==PlayModeStateChange.ExitingPlayMode) Stop("Play Mode exited");
        }
        public static void OnPass(CustomPassContext ctx,bool before)
        {
            var job=current;
            if(job==null||ctx.hdCamera.camera!=job.camera) return;
            int t=Time.frameCount,index;
            if(before)
            {
                if(t==job.lastBefore||job.requested>=job.count)return;
                if(job.director && (job.preparedFrame!=t||job.preparedIndex!=job.requested))return;
                job.lastBefore=t; index=job.requested++; job.activeIndex=index;
                try
                {
                    var grade=GradeSnapshotBridge.Resolve(job.camera,job.shot,index);
                    if(job.director)
                    {
                        grade.timelineFrame=job.startFrame+index;
                        grade.timelineTime=(job.startFrame+index)/(double)job.fps;
                        grade.timelineDirector=job.director.name;
                    }
                    job.grades.Add(grade);
                    GradeSnapshotBridge.Save(grade,Path.Combine(job.folder,"Grade","grade_"+index.ToString("D6")+".json"));
                }
                catch(Exception e) {job.log.Add("Grade frame "+index+": "+e);job.errors++;}
            }
            else
            {
                if(t!=job.lastBefore||job.lastAfter==t||job.activeIndex<0) return;
                job.lastAfter=t;index=job.activeIndex;
            }
            string sub=before?"Clean":"Reference";
            string basename=before?"clean_":"reference_";
            string path=Path.Combine(job.folder,sub,basename+index.ToString("D6")+".exr");
            ExrGpuSaver.Enqueue(ctx,path,(ok,msg)=>
            {
                if(job!=current) return;
                job.readbacks++;
                if(!ok){job.errors++;job.log.Add(msg);}
                Status=job.readbacks+"/"+(job.count*2)+" readbacks";
                if(job.requested==job.count&&job.readbacks==job.count*2) Stop("Completed");
            });
        }
        public static void Stop(string reason)
        {
            var job=current; if(job==null) return;
            current=null;
            CustomPassVolume.UnregisterGlobalCustomPass(job.before);
            CustomPassVolume.UnregisterGlobalCustomPass(job.after);
            Time.captureFramerate=job.oldFramerate;
            EditorApplication.playModeStateChanged-=OnPlayMode;
            try
            {
                if(job.driverObject)UnityEngine.Object.Destroy(job.driverObject);
                if(job.director)
                {
                    job.director.timeUpdateMode=job.oldDirectorMode;
                    if(job.oldDirectorState==PlayState.Playing)
                    {
                        job.director.time=job.oldDirectorTime;
                        job.director.Evaluate();
                        job.director.Resume();
                    }
                    else
                    {
                        job.director.Stop();
                        job.director.time=job.oldDirectorTime;
                    }
                }
            }
            catch(Exception e){job.log.Add("Timeline restoration: "+e.Message);}
            try
            {
                GradeSnapshotBridge.ExportDependencies(job.grades,Path.Combine(job.folder,"Grade","referenced-assets.unitypackage"));
                File.WriteAllText(Path.Combine(job.folder,"capture-report.txt"),
                    "Reason: "+reason+"\nShot: "+job.shot+"\nRequested: "+job.requested+"/"+job.count+
                    "\nTimeline start frame: "+job.startFrame+"\nFPS: "+job.fps+"\nCompleted readbacks: "+job.readbacks+"/"+(job.count*2)+"\nErrors: "+job.errors+
                    "\n"+string.Join("\n",job.log));
            }
            catch(Exception e){Debug.LogException(e);}
            Status=reason+": "+job.readbacks+" EXRs, "+job.errors+" errors -> "+job.folder;
            Debug.Log("[FadoEXR] "+Status);
        }
    }
}
