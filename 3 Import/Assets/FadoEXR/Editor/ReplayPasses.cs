using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;

namespace FadoEXR
{
    [Serializable] public sealed class ReplayImagePass : CustomPass
    {
        Material material;
        protected override void Setup(ScriptableRenderContext context,CommandBuffer cmd)
        {
            var shader=Shader.Find("Hidden/FadoEXR/ReplayImage");
            if(shader)material=CoreUtils.CreateEngineMaterial(shader);
            else Debug.LogError("FadoEXR replay shader not found. Copy Shaders into Assets/FadoEXR.");
        }
        protected override void Execute(CustomPassContext ctx)
        {
            var image=ReplayRunner.InputFor(ctx.hdCamera.camera);
            if(!image||!material)return;
            ctx.propertyBlock.SetTexture("_FadoSource",image);
            ctx.propertyBlock.SetFloat("_FadoFlipY",ReplayRunner.FlipY?1:0);
            CoreUtils.SetRenderTarget(ctx.cmd,ctx.cameraColorBuffer,ClearFlag.None);
            CoreUtils.DrawFullScreen(ctx.cmd,material,ctx.propertyBlock,shaderPassId:0);
        }
        protected override void Cleanup(){if(material)CoreUtils.Destroy(material);material=null;}
    }
    [Serializable] public sealed class ReplayOutputPass : CustomPass
    {
        protected override void Execute(CustomPassContext ctx){ReplayRunner.OutputFor(ctx);}
    }
    public static class ReplayRunner
    {
        sealed class Job
        {
            public Camera camera;
            public List<Texture2D> images;
            public Volume volume;
            public VolumeProfile originalProfile;
            public List<VolumeProfile> profiles;
            public GameObject driverObject;
            public int preparedFrame=-1,preparedIndex=-1;
            public string output;
            public int selected=-1,next,oldFps,saved,errors,lastBefore=-1,lastAfter=-1;
            public ReplayImagePass imagePass;
            public ReplayOutputPass outputPass;
            public List<string> log=new List<string>();
        }
        static Job current;
        public static bool FlipY {get;private set;}
        public static bool Active=>current!=null;
        public static string Status {get;private set;}="Ready";
        public static void Start(Camera cam,List<Texture2D> images,Volume volume,List<VolumeProfile> profiles,string folder,int fps,bool flipY)
        {
            if(Active)throw new InvalidOperationException("Replay already running");
            if(!EditorApplication.isPlaying)throw new InvalidOperationException("Enter Play Mode first");
            if(!cam||images==null||images.Count<1)throw new ArgumentException("Select a camera and source PNG/EXR frames");
            if(!(GraphicsSettings.currentRenderPipeline is HDRenderPipelineAsset))throw new InvalidOperationException("HDRP is required");
            if(!volume||profiles==null||profiles.Count!=images.Count||profiles.Exists(p=>!p))
                throw new ArgumentException("One valid grade Profile is required for every imported frame");
            if(string.IsNullOrEmpty(folder))throw new ArgumentException("Choose an output folder");
            if(Directory.Exists(folder)&&Directory.GetFileSystemEntries(folder).Length>0)
                throw new IOException("Output folder already contains files. Choose an empty output folder.");
            Directory.CreateDirectory(folder);
            FlipY=flipY;
            current=new Job{camera=cam,images=images,output=folder,oldFps=Time.captureFramerate,
                volume=volume,profiles=profiles,originalProfile=volume.sharedProfile,
                imagePass=new ReplayImagePass(),outputPass=new ReplayOutputPass()};
            if(images.Count>1)Time.captureFramerate=Mathf.Clamp(fps,1,60);
            CustomPassVolume.RegisterGlobalCustomPass(CustomPassInjectionPoint.BeforePostProcess,current.imagePass);
            CustomPassVolume.RegisterGlobalCustomPass(CustomPassInjectionPoint.AfterPostProcess,current.outputPass);
            var job=current;
            job.driverObject=new GameObject("FadoEXR Temporary Grade Driver");
            job.driverObject.hideFlags=HideFlags.HideAndDontSave;
            var driver=job.driverObject.AddComponent<FadoFrameDriver>();
            driver.Next=()=>current==job&&job.next<job.images.Count?job.next:-1;
            driver.Prepare=(renderFrame,index)=>
            {
                if(current!=job)return;
                job.volume.sharedProfile=job.profiles[index];
                job.preparedFrame=renderFrame;
                job.preparedIndex=index;
            };
            EditorApplication.playModeStateChanged+=PlayModeChanged;
            Status="Replay armed. Show Game View.";
        }
        static void PlayModeChanged(PlayModeStateChange state){if(state==PlayModeStateChange.ExitingPlayMode)Stop("Play Mode exited");}
        public static Texture2D InputFor(Camera camera)
        {
            var job=current;
            if(job==null||camera!=job.camera)return null;
            int time=Time.frameCount;
            if(job.lastBefore!=time&&job.preparedFrame==time&&job.preparedIndex==job.next)
            {
                job.lastBefore=time;
                job.selected=job.next<job.images.Count?job.next++:-1;
            }
            return job.lastBefore==time&&job.selected>=0?job.images[job.selected]:null;
        }
        public static void OutputFor(CustomPassContext ctx)
        {
            var job=current;
            if(job==null||ctx.hdCamera.camera!=job.camera)return;
            int time=Time.frameCount;
            if(job.lastBefore!=time||job.lastAfter==time||job.selected<0)return;
            job.lastAfter=time;
            var path=Path.Combine(job.output,"regraded_"+job.selected.ToString("D6")+".exr");
            ExrGpuSaver.Enqueue(ctx,path,(ok,msg)=>
            {
                if(job!=current)return;
                job.saved++;
                if(!ok){job.errors++;job.log.Add(msg);}
                Status=job.saved+"/"+job.images.Count+" graded frame(s); "+job.errors+" errors";
                if(job.saved==job.images.Count)Stop("Completed");
            });
        }
        public static void Stop(string why)
        {
            var job=current;if(job==null)return;
            current=null;
            CustomPassVolume.UnregisterGlobalCustomPass(job.imagePass);
            CustomPassVolume.UnregisterGlobalCustomPass(job.outputPass);
            Time.captureFramerate=job.oldFps;
            EditorApplication.playModeStateChanged-=PlayModeChanged;
            try
            {
                if(job.driverObject)UnityEngine.Object.Destroy(job.driverObject);
                if(job.volume)job.volume.sharedProfile=job.originalProfile;
            }
            catch(Exception e){job.log.Add("Volume restoration: "+e.Message);}
            try{File.WriteAllText(Path.Combine(job.output,"replay-report.txt"),
                "Status: "+why+"\nFrames saved: "+job.saved+"/"+job.images.Count+
                "\nGrade frames: "+job.profiles.Count+"\nErrors: "+job.errors+"\n"+string.Join("\n",job.log));}
            catch(Exception e){Debug.LogException(e);}
            Status=why+": "+job.saved+" EXRs, "+job.errors+" errors, "+job.output;
            Debug.Log("[FadoEXR] "+Status);
        }
    }
}
