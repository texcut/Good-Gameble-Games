/* SPDX-License-Identifier: GPL-3.0-or-later
 * Original GGGMac D3D12 diagnostic: hardware adapter, command queue, render-target
 * clear, SM 5.0 and SM 6.0/DXIL draws, texture copy and CPU pixel verification.
 * Original shaders are included; no game data. Presentation is a separate mode.
 * This does not establish Witcher 3 compatibility.
 */
#include <d3d12.h>
#include <dxgi1_4.h>
#include <d3dcompiler.h>
#include "shaders/triangle_dxil.h"
#include "d3d12_present.h"

static void report_d3d12(const char *api, int passed, const char *renderer, const char *version, const char *detail,
                        const char *implementation, const char *shader_model, int binding_tier, const char *ray_tier,
                        const char *shader_target, int presents) {
    printf("GGGMAC_GRAPHICS_JSON:{\"api\":"); quoted(api);
    printf(",\"passed\":%s,\"renderer\":", passed ? "true" : "false"); quoted(renderer);
    printf(",\"version\":"); quoted(version); printf(",\"detail\":"); quoted(detail);
    printf(",\"implementation\":"); quoted(implementation);
    printf(",\"shaderModel\":"); if (*shader_model) quoted(shader_model); else printf("null");
    printf(",\"resourceBindingTier\":"); if (binding_tier) printf("%d", binding_tier); else printf("null");
    printf(",\"rayTracingTier\":"); if (*ray_tier) quoted(ray_tier); else printf("null");
    printf(",\"shaderTarget\":"); quoted(shader_target);
    printf(",\"completedPresents\":"); if (presents >= 0) printf("%d", presents); else printf("null");
    puts("}"); fflush(stdout);
}

static void check_d3d12(int mode) {
    const char *api = mode == 1 ? "d3d12-dxil" : (mode == 2 ? "d3d12-present" : "d3d12");
    int use_dxil = mode != 0;
    const char *shader_target = use_dxil ? "SM 6.0 / DXIL" : "SM 5.0 / DXBC";
    HMODULE module = NULL, dxgi_module = NULL, compiler_module = NULL;
    IDXGIFactory1 *factory = NULL;
    IDXGIAdapter1 *adapter = NULL;
    ID3D12Device *device = NULL;
    ID3D12CommandQueue *queue = NULL;
    ID3D12CommandAllocator *allocator = NULL;
    ID3D12GraphicsCommandList *commands = NULL;
    ID3D12Resource *texture = NULL, *readback = NULL;
    ID3D12DescriptorHeap *descriptors = NULL;
    ID3D12Fence *fence = NULL;
    ID3D12RootSignature *root_signature = NULL;
    ID3D12PipelineState *pipeline = NULL;
    ID3DBlob *vertex_shader = NULL, *pixel_shader = NULL, *signature_blob = NULL, *errors = NULL;
    HANDLE event = NULL;
    char renderer[512] = "", version[64] = "", detail[256] = "";
    char implementation[64] = "Unidentified D3D12 library", shader_model[32] = "", ray_tier[32] = "";
    int binding_tier = 0;
    const char *step = "Load D3D12";
    HRESULT hr = E_FAIL;
    int passed = 0, submitted = 0, completed = 0, presents = mode == 2 ? 0 : -1;
    typedef HRESULT (WINAPI *CreateDevice12)(IUnknown *, D3D_FEATURE_LEVEL, REFIID, void **);
    typedef HRESULT (WINAPI *CreateFactory1)(REFIID, void **);
    typedef HRESULT (WINAPI *CompileShader)(const void *, SIZE_T, const char *, const D3D_SHADER_MACRO *, ID3DInclude *,
        const char *, const char *, UINT, UINT, ID3DBlob **, ID3DBlob **);
    typedef HRESULT (WINAPI *SerializeSignature)(const D3D12_ROOT_SIGNATURE_DESC *, D3D_ROOT_SIGNATURE_VERSION, ID3DBlob **, ID3DBlob **);
    module = LoadLibraryA("d3d12.dll");
    CreateDevice12 create = module ? (CreateDevice12)GetProcAddress(module, "D3D12CreateDevice") : NULL;
    if (!create) {
        snprintf(detail, sizeof(detail), "D3D12CreateDevice is unavailable (Windows error %lu). A Direct3D 12 translation runtime is required.", GetLastError());
        goto done;
    }
    if (!memcmp((const char *)module + 64, "Wine builtin DLL", 16)) strcpy(implementation, "Wine builtin D3D12");
    else strcpy(implementation, "External/native D3D12 library");
    dxgi_module = LoadLibraryA("dxgi.dll");
    CreateFactory1 create_factory = dxgi_module ? (CreateFactory1)GetProcAddress(dxgi_module, "CreateDXGIFactory1") : NULL;
    step = "Create DXGI factory";
    if (!create_factory) goto failed;
    hr = create_factory(&IID_IDXGIFactory1, (void **)&factory);
    if (FAILED(hr)) goto failed;
    step = "Create hardware D3D12 device";
    for (UINT index = 0; IDXGIFactory1_EnumAdapters1(factory, index, &adapter) == S_OK; ++index) {
        DXGI_ADAPTER_DESC1 info;
        hr = IDXGIAdapter1_GetDesc1(adapter, &info);
        if (SUCCEEDED(hr) && !(info.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
            WideCharToMultiByte(CP_UTF8, 0, info.Description, -1, renderer, sizeof(renderer), NULL, NULL);
            hr = create((IUnknown *)adapter, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device);
            if (SUCCEEDED(hr) && device) break;
        }
        IDXGIAdapter1_Release(adapter); adapter = NULL;
    }
    if (!device) { if (SUCCEEDED(hr)) hr = DXGI_ERROR_UNSUPPORTED; goto failed; }
    const D3D_FEATURE_LEVEL requested[] = { D3D_FEATURE_LEVEL_12_2, D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0,
        D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
    D3D12_FEATURE_DATA_FEATURE_LEVELS levels = {5, requested, D3D_FEATURE_LEVEL_11_0};
    if (SUCCEEDED(ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_FEATURE_LEVELS, &levels, sizeof(levels))))
        snprintf(version, sizeof(version), "Feature level %u.%u", (unsigned)levels.MaxSupportedFeatureLevel >> 12,
                 ((unsigned)levels.MaxSupportedFeatureLevel >> 8) & 15);
    D3D12_FEATURE_DATA_SHADER_MODEL shader_caps = {D3D_SHADER_MODEL_6_0};
    if (SUCCEEDED(ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_SHADER_MODEL, &shader_caps, sizeof(shader_caps))))
        snprintf(shader_model, sizeof(shader_model), "%u.%u", (unsigned)shader_caps.HighestShaderModel >> 4, (unsigned)shader_caps.HighestShaderModel & 15);
    D3D12_FEATURE_DATA_D3D12_OPTIONS options = {0};
    if (SUCCEEDED(ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS, &options, sizeof(options))))
        binding_tier = (int)options.ResourceBindingTier;
    D3D12_FEATURE_DATA_D3D12_OPTIONS5 options5 = {0};
    if (SUCCEEDED(ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS5, &options5, sizeof(options5)))) {
        if (!options5.RaytracingTier) strcpy(ray_tier, "Not supported");
        else snprintf(ray_tier, sizeof(ray_tier), "%u.%u", (unsigned)options5.RaytracingTier / 10, (unsigned)options5.RaytracingTier % 10);
    }
    step = "Load HLSL compiler for D3D12 shader draw";
    SerializeSignature serialize = (SerializeSignature)GetProcAddress(module, "D3D12SerializeRootSignature");
    if (!serialize) { hr = E_NOINTERFACE; goto failed; }
    if (!use_dxil) {
    compiler_module = LoadLibraryA("d3dcompiler_47.dll");
    CompileShader compile = compiler_module ? (CompileShader)GetProcAddress(compiler_module, "D3DCompile") : NULL;
    if (!compile) { hr = E_NOINTERFACE; goto failed; }
    const char *vs = "float4 main(uint id : SV_VertexID) : SV_Position { float2 p = id == 0 ? float2(-1,-1) : (id == 1 ? float2(-1,3) : float2(3,-1)); return float4(p,0,1); }";
    const char *ps = "float4 main() : SV_Target { return float4(0.25,0.5,0.75,1.0); }";
    step = "Compile D3D12 vertex shader (SM 5.0)";
    hr = compile(vs, strlen(vs), "GGGMac D3D12 vertex shader", NULL, NULL, "main", "vs_5_0", 0, 0, &vertex_shader, &errors);
    if (FAILED(hr)) goto failed;
    if (errors) { ID3D10Blob_Release(errors); errors = NULL; }
    step = "Compile D3D12 pixel shader (SM 5.0)";
    hr = compile(ps, strlen(ps), "GGGMac D3D12 pixel shader", NULL, NULL, "main", "ps_5_0", 0, 0, &pixel_shader, &errors);
    if (FAILED(hr)) goto failed;
    if (errors) { ID3D10Blob_Release(errors); errors = NULL; }
    }
    D3D12_ROOT_SIGNATURE_DESC signature = {0};
    step = "Create D3D12 root signature";
    hr = serialize(&signature, D3D_ROOT_SIGNATURE_VERSION_1, &signature_blob, &errors);
    if (FAILED(hr)) goto failed;
    hr = ID3D12Device_CreateRootSignature(device, 0, ID3D10Blob_GetBufferPointer(signature_blob), ID3D10Blob_GetBufferSize(signature_blob),
        &IID_ID3D12RootSignature, (void **)&root_signature);
    if (FAILED(hr)) goto failed;
    D3D12_GRAPHICS_PIPELINE_STATE_DESC graphics = {0};
    graphics.pRootSignature = root_signature;
    graphics.VS.pShaderBytecode = use_dxil ? gggmac_dxil_vs : ID3D10Blob_GetBufferPointer(vertex_shader);
    graphics.VS.BytecodeLength = use_dxil ? sizeof(gggmac_dxil_vs) : ID3D10Blob_GetBufferSize(vertex_shader);
    graphics.PS.pShaderBytecode = use_dxil ? gggmac_dxil_ps : ID3D10Blob_GetBufferPointer(pixel_shader);
    graphics.PS.BytecodeLength = use_dxil ? sizeof(gggmac_dxil_ps) : ID3D10Blob_GetBufferSize(pixel_shader);
    graphics.BlendState.RenderTarget[0].SrcBlend = graphics.BlendState.RenderTarget[0].SrcBlendAlpha = D3D12_BLEND_ONE;
    graphics.BlendState.RenderTarget[0].DestBlend = graphics.BlendState.RenderTarget[0].DestBlendAlpha = D3D12_BLEND_ZERO;
    graphics.BlendState.RenderTarget[0].BlendOp = graphics.BlendState.RenderTarget[0].BlendOpAlpha = D3D12_BLEND_OP_ADD;
    graphics.BlendState.RenderTarget[0].LogicOp = D3D12_LOGIC_OP_NOOP;
    graphics.BlendState.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
    graphics.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID; graphics.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
    graphics.RasterizerState.DepthClipEnable = TRUE;
    graphics.DepthStencilState.DepthFunc = D3D12_COMPARISON_FUNC_ALWAYS;
    graphics.DepthStencilState.FrontFace.StencilFunc = graphics.DepthStencilState.BackFace.StencilFunc = D3D12_COMPARISON_FUNC_ALWAYS;
    graphics.DepthStencilState.FrontFace.StencilFailOp = graphics.DepthStencilState.FrontFace.StencilDepthFailOp = graphics.DepthStencilState.FrontFace.StencilPassOp = D3D12_STENCIL_OP_KEEP;
    graphics.DepthStencilState.BackFace = graphics.DepthStencilState.FrontFace;
    graphics.SampleMask = UINT_MAX; graphics.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    graphics.NumRenderTargets = 1; graphics.RTVFormats[0] = DXGI_FORMAT_R8G8B8A8_UNORM; graphics.SampleDesc.Count = 1;
    step = use_dxil ? "Create D3D12 SM 6.0/DXIL graphics pipeline" : "Create D3D12 graphics pipeline";
    hr = ID3D12Device_CreateGraphicsPipelineState(device, &graphics, &IID_ID3D12PipelineState, (void **)&pipeline);
    if (FAILED(hr)) goto failed;
    D3D12_COMMAND_QUEUE_DESC queue_desc = {0}; queue_desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    step = "Create D3D12 command queue";
    hr = ID3D12Device_CreateCommandQueue(device, &queue_desc, &IID_ID3D12CommandQueue, (void **)&queue);
    if (FAILED(hr)) goto failed;
    if (mode == 2) {
        int pending = 0;
        passed = d3d12_window_test(device, factory, pipeline, root_signature, queue, &presents, &pending, detail, sizeof(detail));
        submitted = pending; completed = !pending;
        goto done;
    }
    hr = ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&allocator);
    if (FAILED(hr)) goto failed;
    hr = ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator, NULL,
                                       &IID_ID3D12GraphicsCommandList, (void **)&commands);
    if (FAILED(hr)) goto failed;
    D3D12_HEAP_PROPERTIES heap = {0}; heap.Type = D3D12_HEAP_TYPE_DEFAULT; heap.CreationNodeMask = heap.VisibleNodeMask = 1;
    D3D12_RESOURCE_DESC desc = {0};
    desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D; desc.Width = 4; desc.Height = 4;
    desc.DepthOrArraySize = 1; desc.MipLevels = 1; desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1; desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    D3D12_CLEAR_VALUE clear = {0}; clear.Format = desc.Format;
    clear.Color[3] = 1.0f;
    step = "Create D3D12 render target";
    hr = ID3D12Device_CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE, &desc,
        D3D12_RESOURCE_STATE_RENDER_TARGET, &clear, &IID_ID3D12Resource, (void **)&texture);
    if (FAILED(hr)) goto failed;
    D3D12_DESCRIPTOR_HEAP_DESC descriptor_desc = {0};
    descriptor_desc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV; descriptor_desc.NumDescriptors = 1;
    hr = ID3D12Device_CreateDescriptorHeap(device, &descriptor_desc, &IID_ID3D12DescriptorHeap, (void **)&descriptors);
    if (FAILED(hr)) goto failed;
    D3D12_CPU_DESCRIPTOR_HANDLE rtv = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(descriptors);
    ID3D12Device_CreateRenderTargetView(device, texture, NULL, rtv);
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint;
    UINT64 bytes = 0;
    ID3D12Device_GetCopyableFootprints(device, &desc, 0, 1, 0, &footprint, NULL, NULL, &bytes);
    heap.Type = D3D12_HEAP_TYPE_READBACK;
    D3D12_RESOURCE_DESC buffer = {0};
    buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER; buffer.Width = bytes;
    buffer.Height = buffer.DepthOrArraySize = buffer.MipLevels = buffer.SampleDesc.Count = 1;
    buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    step = "Create D3D12 readback buffer";
    hr = ID3D12Device_CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE, &buffer,
        D3D12_RESOURCE_STATE_COPY_DEST, NULL, &IID_ID3D12Resource, (void **)&readback);
    if (FAILED(hr)) goto failed;
    const FLOAT black[] = {0, 0, 0, 1};
    ID3D12GraphicsCommandList_ClearRenderTargetView(commands, rtv, black, 0, NULL);
    ID3D12GraphicsCommandList_SetPipelineState(commands, pipeline);
    ID3D12GraphicsCommandList_SetGraphicsRootSignature(commands, root_signature);
    ID3D12GraphicsCommandList_OMSetRenderTargets(commands, 1, &rtv, FALSE, NULL);
    D3D12_VIEWPORT viewport = {0, 0, 4, 4, 0, 1}; D3D12_RECT scissor = {0, 0, 4, 4};
    ID3D12GraphicsCommandList_RSSetViewports(commands, 1, &viewport);
    ID3D12GraphicsCommandList_RSSetScissorRects(commands, 1, &scissor);
    ID3D12GraphicsCommandList_IASetPrimitiveTopology(commands, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ID3D12GraphicsCommandList_DrawInstanced(commands, 3, 1, 0, 0);
    D3D12_RESOURCE_BARRIER barrier = {0}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = texture; barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    ID3D12GraphicsCommandList_ResourceBarrier(commands, 1, &barrier);
    D3D12_TEXTURE_COPY_LOCATION destination = {0}, source = {0};
    destination.pResource = readback; destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    destination.PlacedFootprint = footprint;
    source.pResource = texture; source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    ID3D12GraphicsCommandList_CopyTextureRegion(commands, &destination, 0, 0, 0, &source, NULL);
    step = "Close D3D12 command list";
    hr = ID3D12GraphicsCommandList_Close(commands);
    if (FAILED(hr)) goto failed;
    hr = ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence);
    if (FAILED(hr)) goto failed;
    event = CreateEventA(NULL, FALSE, FALSE, NULL);
    if (!event) { strcpy(detail, "Could not create the D3D12 completion event"); goto done; }
    ID3D12CommandList *lists[] = {(ID3D12CommandList *)commands};
    ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists); submitted = 1;
    step = "Signal D3D12 fence";
    hr = ID3D12CommandQueue_Signal(queue, fence, 1);
    if (FAILED(hr)) goto failed;
    hr = ID3D12Fence_SetEventOnCompletion(fence, 1, event);
    if (FAILED(hr)) goto failed;
    if (WaitForSingleObject(event, 15000) != WAIT_OBJECT_0) {
        strcpy(detail, "D3D12 GPU commands did not complete within 15 seconds"); goto done;
    }
    completed = 1;
    step = "Validate D3D12 device after GPU completion";
    hr = ID3D12Device_GetDeviceRemovedReason(device);
    if (FAILED(hr)) goto failed;
    void *mapped = NULL;
    D3D12_RANGE read_range = {(SIZE_T)footprint.Offset, (SIZE_T)footprint.Offset + 4};
    step = "Map D3D12 pixel readback";
    hr = ID3D12Resource_Map(readback, 0, &read_range, &mapped);
    if (FAILED(hr)) goto failed;
    passed = expected_pixel((const unsigned char *)mapped + footprint.Offset) &&
        !strstr(renderer, "llvmpipe") && !strstr(renderer, "softpipe");
    D3D12_RANGE no_writes = {0, 0}; ID3D12Resource_Unmap(readback, 0, &no_writes);
    snprintf(detail, sizeof(detail), "%s", passed
        ? (mode == 1 ? "D3D12 SM 6.0/DXIL vertex/pixel shader execution, copy, fence and pixel readback passed. Game shaders, presentation and ray tracing are not established."
                     : "D3D12 SM 5.0 vertex/pixel shader draw, texture copy, fence completion and pixel readback passed. See the separate DXIL and presentation checks.")
        : "D3D12 pixel readback did not match the expected color, or a software adapter was reported");
    goto done;
failed:
    if (errors) fprintf(stderr, "Shader diagnostic: %.*s\n", (int)(ID3D10Blob_GetBufferSize(errors) > 2048 ? 2048 : ID3D10Blob_GetBufferSize(errors)), (const char *)ID3D10Blob_GetBufferPointer(errors));
    snprintf(detail, sizeof(detail), "%s failed (0x%08lx). Check the D3D12 runtime and Activity log.", step, (unsigned long)hr);
done:
    report_d3d12(api, passed, renderer, version, detail, implementation, shader_model, binding_tier, ray_tier, shader_target, presents);
    /* On device loss or timeout, let process teardown own pending GPU resources.
       Releasing resources referenced by an unfinished command list is unsafe. */
    if (submitted && !completed) return;
    if (event) CloseHandle(event);
    if (fence) ID3D12Fence_Release(fence);
    if (errors) ID3D10Blob_Release(errors);
    if (signature_blob) ID3D10Blob_Release(signature_blob);
    if (pixel_shader) ID3D10Blob_Release(pixel_shader);
    if (vertex_shader) ID3D10Blob_Release(vertex_shader);
    if (pipeline) ID3D12PipelineState_Release(pipeline);
    if (root_signature) ID3D12RootSignature_Release(root_signature);
    if (descriptors) ID3D12DescriptorHeap_Release(descriptors);
    if (readback) ID3D12Resource_Release(readback);
    if (texture) ID3D12Resource_Release(texture);
    if (commands) ID3D12GraphicsCommandList_Release(commands);
    if (allocator) ID3D12CommandAllocator_Release(allocator);
    if (queue) ID3D12CommandQueue_Release(queue);
    if (device) ID3D12Device_Release(device);
    if (adapter) IDXGIAdapter1_Release(adapter);
    if (factory) IDXGIFactory1_Release(factory);
    if (dxgi_module) FreeLibrary(dxgi_module);
    if (module) FreeLibrary(module);
    if (compiler_module) FreeLibrary(compiler_module);
}
