using System;
using UnityEngine;
namespace FadoEXR
{
    // Execute before Cinemachine LateUpdate so Timeline camera changes can propagate.
    [DefaultExecutionOrder(-32000)]
    public sealed class FadoFrameDriver : MonoBehaviour
    {
        public Func<int> Next;
        public Action<int,int> Prepare;
        void LateUpdate()
        {
            int index = Next != null ? Next() : -1;
            if (index >= 0 && Prepare != null) Prepare(Time.frameCount,index);
        }
    }
}
