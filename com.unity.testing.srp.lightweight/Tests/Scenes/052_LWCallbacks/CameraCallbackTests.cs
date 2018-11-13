using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.LightweightPipeline;
using UnityEngine.Rendering;

internal class CopyDepthPass : ScriptableRenderPass
{
    private RenderTargetHandle source { get; set; }
    private RenderTargetHandle destination { get; set; }

    const string k_DepthCopyTag = "Copy Depth";

    public void Setup(RenderTargetHandle source, RenderTargetHandle destination)
    {
        this.source = source;
        this.destination = destination;
    }

    public override void Execute(ScriptableRenderer renderer, ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (renderer == null)
            throw new ArgumentNullException("renderer");

        CommandBuffer cmd = CommandBufferPool.Get(k_DepthCopyTag);
        RenderTargetIdentifier depthSurface = source.Identifier();
        RenderTargetIdentifier copyDepthSurface = destination.Identifier();
        Material depthCopyMaterial = renderer.GetMaterial(MaterialHandle.CopyDepth);

        RenderTextureDescriptor descriptor = ScriptableRenderer.CreateRenderTextureDescriptor(ref renderingData.cameraData);
        descriptor.colorFormat = RenderTextureFormat.Depth;
        descriptor.depthBufferBits = 32; //TODO: fix this ;
        descriptor.msaaSamples = 1;
        descriptor.bindMS = false;
        cmd.GetTemporaryRT(destination.id, descriptor, FilterMode.Point);

        cmd.SetGlobalTexture("_CameraDepthAttachment", source.Identifier());

        if (renderingData.cameraData.msaaSamples > 1)
        {
            cmd.DisableShaderKeyword(ShaderKeywordStrings.DepthNoMsaa);
            if (renderingData.cameraData.msaaSamples == 4)
            {
                cmd.DisableShaderKeyword(ShaderKeywordStrings.DepthMsaa2);
                cmd.EnableShaderKeyword(ShaderKeywordStrings.DepthMsaa4);
            }
            else
            {
                cmd.EnableShaderKeyword(ShaderKeywordStrings.DepthMsaa2);
                cmd.DisableShaderKeyword(ShaderKeywordStrings.DepthMsaa4);
            }
            cmd.Blit(depthSurface, copyDepthSurface, depthCopyMaterial);
        }
        else
        {
            cmd.EnableShaderKeyword(ShaderKeywordStrings.DepthNoMsaa);
            cmd.DisableShaderKeyword(ShaderKeywordStrings.DepthMsaa2);
            cmd.DisableShaderKeyword(ShaderKeywordStrings.DepthMsaa4);
            ScriptableRenderer.CopyTexture(cmd, depthSurface, copyDepthSurface, depthCopyMaterial);
        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd)
    {
        if (cmd == null)
            throw new ArgumentNullException("cmd");

        if (destination != RenderTargetHandle.CameraTarget)
        {
            cmd.ReleaseTemporaryRT(destination.id);
            destination = RenderTargetHandle.CameraTarget;
        }
    }
}

internal class CopyColorPass : ScriptableRenderPass
{
    const string k_CopyColorTag = "Copy Color";
    float[] m_OpaqueScalerValues = {1.0f, 0.5f, 0.25f, 0.25f};
    int m_SampleOffsetShaderHandle;

    private RenderTargetHandle source { get; set; }
    private RenderTargetHandle destination { get; set; }

    public CopyColorPass()
    {
        m_SampleOffsetShaderHandle = Shader.PropertyToID("_SampleOffset");
    }

    public void Setup(RenderTargetHandle source, RenderTargetHandle destination)
    {
        this.source = source;
        this.destination = destination;
    }

    /// <inheritdoc/>
    public override void Execute(ScriptableRenderer renderer, ScriptableRenderContext context,
        ref RenderingData renderingData)
    {
        if (renderer == null)
            throw new ArgumentNullException("renderer");

        CommandBuffer cmd = CommandBufferPool.Get(k_CopyColorTag);
        Downsampling downsampling = renderingData.cameraData.opaqueTextureDownsampling;
        float opaqueScaler = m_OpaqueScalerValues[(int) downsampling];

        RenderTextureDescriptor opaqueDesc =
            ScriptableRenderer.CreateRenderTextureDescriptor(ref renderingData.cameraData, opaqueScaler);
        RenderTargetIdentifier colorRT = source.Identifier();
        RenderTargetIdentifier opaqueColorRT = destination.Identifier();

        cmd.GetTemporaryRT(destination.id, opaqueDesc,
            renderingData.cameraData.opaqueTextureDownsampling == Downsampling.None
                ? FilterMode.Point
                : FilterMode.Bilinear);
        switch (downsampling)
        {
            case Downsampling.None:
                cmd.Blit(colorRT, opaqueColorRT);
                break;
            case Downsampling._2xBilinear:
                cmd.Blit(colorRT, opaqueColorRT);
                break;
            case Downsampling._4xBox:
                Material samplingMaterial = renderer.GetMaterial(MaterialHandle.Sampling);
                samplingMaterial.SetFloat(m_SampleOffsetShaderHandle, 2);
                cmd.Blit(colorRT, opaqueColorRT, samplingMaterial, 0);
                break;
            case Downsampling._4xBilinear:
                cmd.Blit(colorRT, opaqueColorRT);
                break;
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void FrameCleanup(CommandBuffer cmd)
    {
        if (cmd == null)
            throw new ArgumentNullException("cmd");

        if (destination != RenderTargetHandle.CameraTarget)
        {
            cmd.ReleaseTemporaryRT(destination.id);
            destination = RenderTargetHandle.CameraTarget;
        }
    }
}

public class CameraCallbackTests : MonoBehaviour
	, IAfterDepthPrePass
	, IAfterOpaquePass
	, IAfterOpaquePostProcess
	, IAfterSkyboxPass
	, IAfterTransparentPass
	, IAfterRender
{
	
	static RenderTargetHandle afterDepth;
	static RenderTargetHandle afterOpaque;
	static RenderTargetHandle afterOpaquePost;
	static RenderTargetHandle afterSkybox;
	static RenderTargetHandle afterTransparent;
	static RenderTargetHandle afterAll;

	public CameraCallbackTests()
	{
		afterDepth.Init("_AfterDepth");
		afterOpaque.Init("_AfterOpaque");
		afterOpaquePost.Init("_AfterOpaquePost");
		afterSkybox.Init("_AfterSkybox");
		afterTransparent.Init("_AfterTransparent");
		afterAll.Init("_AfterAll");
	}
	
	
	ScriptableRenderPass IAfterDepthPrePass.GetPassToEnqueue(RenderTextureDescriptor baseDescriptor, RenderTargetHandle depthAttachmentHandle)
	{
		var pass = new CopyDepthPass();
		pass.Setup(depthAttachmentHandle, afterDepth);
		return pass;
	}

	ScriptableRenderPass IAfterOpaquePass.GetPassToEnqueue(RenderTextureDescriptor baseDescriptor, RenderTargetHandle colorAttachmentHandle,
		RenderTargetHandle depthAttachmentHandle)
	{
		var pass = new CopyColorPass();
		pass.Setup(colorAttachmentHandle, afterOpaque);
		return pass;
	}

	ScriptableRenderPass IAfterOpaquePostProcess.GetPassToEnqueue(RenderTextureDescriptor baseDescriptor, RenderTargetHandle colorHandle,
		RenderTargetHandle depthHandle)
	{
		var pass = new CopyColorPass();;
		pass.Setup(colorHandle, afterOpaquePost);
		return pass;
	}

	ScriptableRenderPass IAfterSkyboxPass.GetPassToEnqueue(RenderTextureDescriptor baseDescriptor, RenderTargetHandle colorHandle,
		RenderTargetHandle depthHandle)
	{
		var pass = new CopyColorPass();
		pass.Setup(colorHandle, afterSkybox);
		return pass;
	}

	ScriptableRenderPass IAfterTransparentPass.GetPassToEnqueue(RenderTextureDescriptor baseDescriptor, RenderTargetHandle colorHandle,
		RenderTargetHandle depthHandle)
	{
		var pass = new CopyColorPass();
		pass.Setup(colorHandle, afterTransparent);
		return pass;
	}

	class BlitPass : ScriptableRenderPass
	{
        private RenderTargetHandle colorHandle;
        private RenderTargetHandle depthHandle;

        public BlitPass(RenderTargetHandle colorHandle, RenderTargetHandle depthHandle)
        {
            this.colorHandle = colorHandle;
            this.depthHandle = colorHandle;
        }

        public override void Execute(ScriptableRenderer renderer, ScriptableRenderContext context, ref RenderingData renderingData)
		{
			if (renderer == null)
				throw new ArgumentNullException("renderer");

		    var pass = new CopyColorPass();
		    pass.Setup(colorHandle, afterAll);
            pass.Execute(renderer, context, ref renderingData);

            Material material = renderer.GetMaterial(MaterialHandle.Blit);

			CommandBuffer cmd = CommandBufferPool.Get("Blit Pass");
			cmd.SetRenderTarget(colorHandle.id, depthHandle.id);
			cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
			
			cmd.SetViewport(new Rect(0, renderingData.cameraData.camera.pixelRect.height / 2.0f, renderingData.cameraData.camera.pixelRect.width / 3.0f, renderingData.cameraData.camera.pixelRect.height / 2.0f));
			cmd.SetGlobalTexture("_BlitTex", afterDepth.Identifier());
		    ScriptableRenderer.RenderFullscreenQuad(cmd, material);
			
			cmd.SetViewport(new Rect(renderingData.cameraData.camera.pixelRect.width / 3.0f, renderingData.cameraData.camera.pixelRect.height / 2.0f, renderingData.cameraData.camera.pixelRect.width / 3.0f, renderingData.cameraData.camera.pixelRect.height / 2.0f));
			cmd.SetGlobalTexture("_BlitTex", afterOpaque.Identifier());
		    ScriptableRenderer.RenderFullscreenQuad(cmd, material);
			
			cmd.SetViewport(new Rect(renderingData.cameraData.camera.pixelRect.width / 3.0f * 2.0f, renderingData.cameraData.camera.pixelRect.height / 2.0f, renderingData.cameraData.camera.pixelRect.width / 3.0f, renderingData.cameraData.camera.pixelRect.height / 2.0f));
			cmd.SetGlobalTexture("_BlitTex", afterOpaquePost.Identifier());
		    ScriptableRenderer.RenderFullscreenQuad(cmd, material);			
						
			cmd.SetViewport(new Rect(0f, 0f, renderingData.cameraData.camera.pixelRect.width / 3.0f, renderingData.cameraData.camera.pixelRect.height / 2.0f));
			cmd.SetGlobalTexture("_BlitTex", afterSkybox.Identifier());
		    ScriptableRenderer.RenderFullscreenQuad(cmd, material);
			
			cmd.SetViewport(new Rect(renderingData.cameraData.camera.pixelRect.width / 3.0f, 0f, renderingData.cameraData.camera.pixelRect.width / 3.0f, renderingData.cameraData.camera.pixelRect.height / 2.0f));
			cmd.SetGlobalTexture("_BlitTex", afterTransparent.Identifier());
		    ScriptableRenderer.RenderFullscreenQuad(cmd, material);
			
			cmd.SetViewport(new Rect(renderingData.cameraData.camera.pixelRect.width / 3.0f * 2.0f, 0f, renderingData.cameraData.camera.pixelRect.width / 3.0f, renderingData.cameraData.camera.pixelRect.height / 2.0f));
			cmd.SetGlobalTexture("_BlitTex", afterAll.Identifier());
		    ScriptableRenderer.RenderFullscreenQuad(cmd, material);

            context.ExecuteCommandBuffer(cmd);
			CommandBufferPool.Release(cmd);
		}

		public override void FrameCleanup(CommandBuffer cmd)
		{
			if (cmd == null)
				throw new ArgumentNullException("cmd");
			
			base.FrameCleanup(cmd);
		}
	}

	ScriptableRenderPass IAfterRender.GetPassToEnqueue(RenderTextureDescriptor baseDescriptor, RenderTargetHandle colorHandle, RenderTargetHandle depthHandle)
	{
		return new BlitPass(colorHandle, depthHandle);
	}
}
