import SwiftUI
import MetalKit

// The same struct we defined in SiriWave.metal
struct SiriWaveUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var talkingFactor: Float
}

public struct SiriMetalView: UIViewRepresentable {
    var talkingFactor: Double
    var phase: Double
    
    public init(talkingFactor: Double, phase: Double) {
        self.talkingFactor = talkingFactor
        self.phase = phase
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        
        if let device = MTLCreateSystemDefaultDevice() {
            mtkView.device = device
        }
        
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.framebufferOnly = true
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.backgroundColor = .clear
        mtkView.isOpaque = false
        // Critical: otherwise the full drawable reads as an opaque box over glass.
        if let metalLayer = mtkView.layer as? CAMetalLayer {
            metalLayer.isOpaque = false
        }
        
        context.coordinator.setupMetal(mtkView: mtkView)
        
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.parent = self
    }
    
    public class Coordinator: NSObject, MTKViewDelegate {
        var parent: SiriMetalView
        
        var device: MTLDevice?
        var commandQueue: MTLCommandQueue?
        var pipelineState: MTLRenderPipelineState?
        
        init(_ parent: SiriMetalView) {
            self.parent = parent
        }
        
        func setupMetal(mtkView: MTKView) {
            self.device = mtkView.device
            guard let device = self.device else { return }
            
            self.commandQueue = device.makeCommandQueue()
            
            let metalSource = """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float2 uv;
            };

            struct Uniforms {
                float2 resolution;
                float time;
                float talkingFactor;
            };

            vertex VertexOut siriVertexShader(uint vertexID [[vertex_id]]) {
                float2 positions[6] = {
                    float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
                    float2( 1.0,  1.0), float2(-1.0,  1.0), float2( 1.0, -1.0)
                };
                float2 uvs[6] = {
                    float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
                    float2(1.0, 0.0), float2(0.0, 0.0), float2(1.0, 1.0)
                };
                VertexOut out;
                out.position = float4(positions[vertexID], 0.0, 1.0);
                out.uv = uvs[vertexID];
                return out;
            }

            constant float PI = 3.14159265359f;
            // Idle still flows as a visible rainbow ribbon; speech grows amplitude.
            constant float AMPLITUDE   = 0.14f;
            constant float FREQ        = 0.85f;
            constant float ABER_FREQ   = 0.78f;
            constant float SPEED       = 2.4f;
            constant float WAVE_SCALE  = 0.6f;
            constant float ABERRATION  = 3.1f;
            constant float THICKNESS   = 0.55f;
            constant float INTENSITY   = 2.35f;
            constant float FALLOFF     = 0.85f;
            constant float EDGE_MASK   = 0.4f;
            constant float EDGE_INSET  = 0.0f;
            constant float BAND_FILL   = 18000.0f;
            constant float BAND_THICK  = 0.07f;
            constant float SOFTNESS    = 0.22f;
            constant float LOW_AMP     = 18.0f;
            constant float LOW_INT     = 1.5f;
            constant float MID_ABER    = 0.95f;
            constant float MID_ABAMP   = 0.05f;
            constant float MID_BAND    = 20.0f;
            constant float MID_SOFT    = 0.25f;
            constant float HIGH_ABER   = 0.65f;
            constant float HIGH_ABAMP  = 0.06f;
            constant float RESOLVED    = 1.0f;
            constant float UNRES_SCALE = 0.14f;
            constant float Y_OFFSET    = -0.08f;
            
            float3 spectral4(int s){
                // Distinct primaries — avoid collapsing toward white.
                if (s == 0) return float3(1.00f, 0.18f, 0.55f); // magenta/red
                if (s == 1) return float3(1.00f, 0.72f, 0.12f); // amber
                if (s == 2) return float3(0.18f, 0.95f, 0.55f); // green
                return float3(0.25f, 0.55f, 1.00f);             // blue
            }

            fragment half4 siriFragmentShader(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
                float2 uv = in.uv * 2.0f - 1.0f;
                float aspect = u.resolution.x / u.resolution.y;
                float2 p = uv;
                float yScreen = uv.y;
                p.y += Y_OFFSET;
                p.y *= 1.2f;
                p.x *= aspect;
                p /= max(WAVE_SCALE, 0.1f);
                float t = u.time;
                float talkingFactor = u.talkingFactor;
                
                float low  = clamp(0.45f + 0.45f*sin(t*0.8f)*sin(t*0.37f+1.0f), 0.0f, 1.0f);
                float mid  = clamp(0.40f + 0.40f*sin(t*1.7f+2.0f)*sin(t*0.53f), 0.0f, 1.0f);
                float high = clamp(0.30f + 0.30f*sin(t*2.9f+4.0f)*sin(t*0.71f+2.0f), 0.0f, 1.0f);
                
                float activeFactor = pow(clamp(talkingFactor, 0.0f, 1.0f), 0.72f);
                
                float res   = clamp(RESOLVED, 0.0f, 1.0f);
                float drift = fmod(t, 20.0f * PI) * SPEED;
                float xN  = p.x / max(aspect, 1.0f);
                
                float xNorm = min(abs(uv.x * 1.15f), 1.0f);
                float env = cos(PI*0.5f * xNorm);
                
                float dynamicLowAmp = activeFactor * LOW_AMP * 5.0f;
                float dynamicMidAmp = activeFactor * MID_ABAMP * 5.0f;
                float dynamicHighAmp = activeFactor * HIGH_ABAMP * 5.0f;
                
                float A1    = AMPLITUDE + 0.01f*low*dynamicLowAmp;
                float A2    = A1 + mid*dynamicMidAmp + high*dynamicHighAmp;
                float AB    = (ABERRATION + mid*MID_ABER + high*HIGH_ABER)*res;
                
                // Keep strong chromatic split even when idle so the ribbon stays rainbow.
                AB *= mix(0.70f, 1.0f, clamp(activeFactor * 3.0f, 0.0f, 1.0f));
                
                float currentThickness = THICKNESS + (activeFactor * 5.5f);
                float th    = mix(0.1f, 0.01f*currentThickness, res);
                float inten = mix(0.1f, 0.01f*(INTENSITY + low*LOW_INT), res);
                
                // Minimal idle soft glow — soft white haze was washing the rainbow.
                float idleGlowBoost = 0.35f * (1.0f - clamp(activeFactor * 2.0f, 0.0f, 1.0f));
                float soft  = 0.01f*res*max(0.0f, SOFTNESS + idleGlowBoost + mid*MID_SOFT);
                
                float dUnres = max(length(p) - mix(0.14f, UNRES_SCALE, res), 0.0f);
                float yMain = A1 * env * res * sin(p.x*FREQ + drift);
                float bandFillTh = max(BAND_THICK, 1e-4f);
                float bandAmt    = 1e-4f * BAND_FILL * inten;
                float3 num = float3(0.0f);
                float3 den = float3(0.0f);
                for(int s = 0; s < 4; s++){
                    float3 hue = spectral4(s);
                    den += hue;
                    float ab = mix(-AB, AB, float(s)/3.0f);
                    float yL = A2 * env * res * sin(p.x*ABER_FREQ + drift + ab);
                    float d   = mix(dUnres, abs(p.y - yL), res);
                    float lor = mix(1.0f/(1.0f + (0.02f*d)*(0.02f*d)), 1.0f, res);
                    float line = inten / (sqrt(d*d + soft*soft) + th);
                    float lo = min(yMain, yL), hi = max(yMain, yL);
                    float dBand = max(0.0f, max(p.y - hi, lo - p.y));
                    float band  = bandAmt / (dBand + bandFillTh);
                    num += hue * lor * (line + band);
                }
                float3 col = num / max(den, float3(1e-4f));
                float dM    = mix(dUnres, abs(p.y - yMain), res);
                float lorM  = mix(1.0f/(1.0f + (0.02f*dM)*(0.02f*dM)), 1.0f, res);
                // Colored core boost — do not add a white/neutral core.
                float core = 0.22f * inten * lorM / (sqrt(dM*dM + soft*soft) + th);
                col += col * core;
                col = pow(max(col, 0.0f), float3(0.92f));
                float emT = clamp((abs(yScreen) - 1.0f + EDGE_INSET) / (-max(EDGE_MASK, 1e-4f)), 0.0f, 1.0f);
                float em  = emT*emT*(3.0f - 2.0f*emT);
                float gauss = exp(-pow(xN*FALLOFF, 2.0f));
                col *= mix(1.0f, em*gauss, res);
                col *= res;
                // Idle stays colorful; talking adds punch without bleaching.
                col *= 1.15f + (activeFactor * 0.95f);
                float luma = dot(col, float3(0.299f, 0.587f, 0.114f));
                col = mix(float3(luma), col, 1.35f);
                col = clamp(col, 0.0f, 1.8f);
                
                // Per-pixel alpha so the MTKView isn't an opaque white/washed box.
                // Premultiply RGB for the .one / .oneMinusSourceAlpha blend.
                float alpha = clamp(max(max(col.r, col.g), col.b), 0.0f, 1.0f);
                alpha = pow(alpha, 0.78f);
                float3 outRGB = min(col, float3(1.0f)) * alpha;
                return half4(half3(outRGB), half(alpha));
            }
            """
            
            guard let validLibrary = try? device.makeLibrary(source: metalSource, options: nil) else {
                print("LiquidSiri: Failed to compile Metal string")
                return
            }
            
            guard let vertexFunc = validLibrary.makeFunction(name: "siriVertexShader"),
                  let fragmentFunc = validLibrary.makeFunction(name: "siriFragmentShader") else {
                print("LiquidSiri: Failed to find shader functions")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            
            // Premultiplied-friendly blending: transparent outside the ribbon
            // (avoids the opaque MTKView box) while keeping additive glow punch.
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                print("LiquidSiri: Failed to create pipeline state: \(error)")
            }
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize if needed
        }
        
        public func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let pipelineState = pipelineState,
                  let commandQueue = commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            
            // Set up uniforms
            let width = Float(view.drawableSize.width)
            let height = Float(view.drawableSize.height)
            
            var uniforms = SiriWaveUniforms(
                resolution: SIMD2<Float>(width, height),
                time: Float(parent.phase),
                talkingFactor: Float(parent.talkingFactor)
            )
            
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<SiriWaveUniforms>.stride, index: 0)
            
            // Draw full screen quad (6 vertices defined in vertex shader)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
