Shader "Hidden/FadoEXR/ReplayImage"
{
    SubShader
    {
        Tags { "RenderPipeline"="HDRenderPipeline" }
        Pass
        {
            ZTest Always ZWrite Off Cull Off
            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex Vert
            #pragma fragment Frag
            Texture2D<float4> _FadoSource;
            SamplerState sampler_FadoSource;
            float _FadoFlipY;
            struct Attributes { uint vertexID: SV_VertexID; };
            struct Varyings { float4 pos:SV_POSITION; float2 uv:TEXCOORD0; };
            Varyings Vert(Attributes v)
            {
                Varyings o;
                float2 uv=float2((v.vertexID<<1)&2,v.vertexID&2);
                o.pos=float4(uv*2-1,0,1);
                o.uv=uv;
                if(_FadoFlipY>0.5)o.uv.y=1-o.uv.y;
                return o;
            }
            float4 Frag(Varyings v):SV_Target
            {
                return _FadoSource.SampleLevel(sampler_FadoSource,v.uv,0);
            }
            ENDHLSL
        }
    }
    Fallback Off
}
