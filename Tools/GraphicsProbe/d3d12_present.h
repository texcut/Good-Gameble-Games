/* SPDX-License-Identifier: GPL-3.0-or-later
 * Original bounded D3D12 swap-chain test. Each frame is drawn, copied, checked,
 * and presented. A successful Present API call is not human visual validation.
 */
static LRESULT CALLBACK gggmac_probe_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_CLOSE) { DestroyWindow(window); return 0; }
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(window, message, wparam, lparam);
}

static int d3d12_window_test(ID3D12Device *device, IDXGIFactory1 *factory, ID3D12PipelineState *pipeline,
        ID3D12RootSignature *signature, ID3D12CommandQueue *queue, int *presents, int *pending,
        char *detail, size_t detail_size) {
    IDXGIFactory2 *factory2 = NULL;
    IDXGISwapChain1 *swap1 = NULL;
    IDXGISwapChain3 *swap = NULL;
    ID3D12Resource *buffers[2] = {NULL, NULL}, *readback = NULL;
    ID3D12DescriptorHeap *views = NULL;
    ID3D12CommandAllocator *allocator = NULL;
    ID3D12GraphicsCommandList *commands = NULL;
    ID3D12Fence *fence = NULL;
    HWND window = NULL; HANDLE event = NULL;
    HRESULT hr = E_FAIL;
    const char *step = "Create D3D12 window";
    int passed = 0;
    WNDCLASSA cls = {0};
    cls.lpfnWndProc = gggmac_probe_window_proc; cls.hInstance = GetModuleHandle(NULL);
    cls.lpszClassName = "GGGMacD3D12Presentation"; cls.hCursor = LoadCursor(NULL, IDC_ARROW);
    if (!RegisterClassA(&cls)) goto failed;
    DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    RECT size = {0, 0, 640, 360}; AdjustWindowRect(&size, style, FALSE);
    window = CreateWindowA(cls.lpszClassName, "GGGMac Direct3D 12 presentation check", style,
        CW_USEDEFAULT, CW_USEDEFAULT, size.right - size.left, size.bottom - size.top, NULL, NULL, cls.hInstance, NULL);
    if (!window) goto failed;
    step = "Create DXGI swap-chain factory";
    hr = IDXGIFactory1_QueryInterface(factory, &IID_IDXGIFactory2, (void **)&factory2);
    if (FAILED(hr)) goto failed;
    DXGI_SWAP_CHAIN_DESC1 desc = {0};
    desc.Width = 640; desc.Height = 360; desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1; desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2; desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    step = "Create D3D12 window swap chain";
    hr = IDXGIFactory2_CreateSwapChainForHwnd(factory2, (IUnknown *)queue, window, &desc, NULL, NULL, &swap1);
    if (FAILED(hr)) goto failed;
    hr = IDXGISwapChain1_QueryInterface(swap1, &IID_IDXGISwapChain3, (void **)&swap);
    if (FAILED(hr)) goto failed;
    D3D12_DESCRIPTOR_HEAP_DESC heap_desc = {0};
    heap_desc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV; heap_desc.NumDescriptors = 2;
    step = "Create swap-chain render targets";
    hr = ID3D12Device_CreateDescriptorHeap(device, &heap_desc, &IID_ID3D12DescriptorHeap, (void **)&views);
    if (FAILED(hr)) goto failed;
    D3D12_CPU_DESCRIPTOR_HANDLE first_view = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(views);
    UINT stride = ID3D12Device_GetDescriptorHandleIncrementSize(device, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    for (UINT index = 0; index < 2; ++index) {
        hr = IDXGISwapChain3_GetBuffer(swap, index, &IID_ID3D12Resource, (void **)&buffers[index]);
        if (FAILED(hr)) goto failed;
        D3D12_CPU_DESCRIPTOR_HANDLE view = {first_view.ptr + index * stride};
        ID3D12Device_CreateRenderTargetView(device, buffers[index], NULL, view);
    }
    D3D12_RESOURCE_DESC back_desc = ID3D12Resource_GetDesc(buffers[0]);
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint; UINT64 bytes = 0;
    ID3D12Device_GetCopyableFootprints(device, &back_desc, 0, 1, 0, &footprint, NULL, NULL, &bytes);
    D3D12_HEAP_PROPERTIES heap = {0}; heap.Type = D3D12_HEAP_TYPE_READBACK; heap.CreationNodeMask = heap.VisibleNodeMask = 1;
    D3D12_RESOURCE_DESC read_desc = {0};
    read_desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER; read_desc.Width = bytes;
    read_desc.Height = read_desc.DepthOrArraySize = read_desc.MipLevels = read_desc.SampleDesc.Count = 1;
    read_desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    hr = ID3D12Device_CreateCommittedResource(device, &heap, D3D12_HEAP_FLAG_NONE, &read_desc,
        D3D12_RESOURCE_STATE_COPY_DEST, NULL, &IID_ID3D12Resource, (void **)&readback);
    if (FAILED(hr)) goto failed;
    hr = ID3D12Device_CreateCommandAllocator(device, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&allocator);
    if (FAILED(hr)) goto failed;
    hr = ID3D12Device_CreateCommandList(device, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator, pipeline,
        &IID_ID3D12GraphicsCommandList, (void **)&commands);
    if (FAILED(hr)) goto failed;
    hr = ID3D12Device_CreateFence(device, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence);
    if (FAILED(hr)) goto failed;
    event = CreateEventA(NULL, FALSE, FALSE, NULL);
    if (!event) goto failed;
    ShowWindow(window, SW_SHOWNORMAL);
    for (UINT frame = 0; frame < 60; ++frame) {
        MSG message;
        while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE)) {
            if (message.message != WM_QUIT) { TranslateMessage(&message); DispatchMessageA(&message); }
        }
        if (!IsWindow(window) || !IsWindowVisible(window) || IsIconic(window)) {
            snprintf(detail, detail_size, "Presentation check stopped: the test window was closed, hidden or minimized after %d frames", *presents);
            goto done;
        }
        if (frame) {
            step = "Reset D3D12 frame allocator";
            hr = ID3D12CommandAllocator_Reset(allocator); if (FAILED(hr)) goto failed;
            hr = ID3D12GraphicsCommandList_Reset(commands, allocator, pipeline); if (FAILED(hr)) goto failed;
        }
        UINT index = IDXGISwapChain3_GetCurrentBackBufferIndex(swap);
        if (index >= 2) { hr = E_UNEXPECTED; goto failed; }
        D3D12_CPU_DESCRIPTOR_HANDLE view = {first_view.ptr + index * stride};
        D3D12_RESOURCE_BARRIER barrier = {0}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition.pResource = buffers[index]; barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT; barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
        ID3D12GraphicsCommandList_ResourceBarrier(commands, 1, &barrier);
        const FLOAT black[] = {0, 0, 0, 1};
        ID3D12GraphicsCommandList_ClearRenderTargetView(commands, view, black, 0, NULL);
        ID3D12GraphicsCommandList_SetGraphicsRootSignature(commands, signature);
        ID3D12GraphicsCommandList_OMSetRenderTargets(commands, 1, &view, FALSE, NULL);
        D3D12_VIEWPORT viewport = {0, 0, (FLOAT)back_desc.Width, (FLOAT)back_desc.Height, 0, 1};
        D3D12_RECT scissor = {0, 0, (LONG)back_desc.Width, (LONG)back_desc.Height};
        ID3D12GraphicsCommandList_RSSetViewports(commands, 1, &viewport);
        ID3D12GraphicsCommandList_RSSetScissorRects(commands, 1, &scissor);
        ID3D12GraphicsCommandList_IASetPrimitiveTopology(commands, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        ID3D12GraphicsCommandList_DrawInstanced(commands, 3, 1, 0, 0);
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET; barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
        ID3D12GraphicsCommandList_ResourceBarrier(commands, 1, &barrier);
        D3D12_TEXTURE_COPY_LOCATION destination = {0}, source = {0};
        destination.pResource = readback; destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; destination.PlacedFootprint = footprint;
        source.pResource = buffers[index]; source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        ID3D12GraphicsCommandList_CopyTextureRegion(commands, &destination, 0, 0, 0, &source, NULL);
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE; barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        ID3D12GraphicsCommandList_ResourceBarrier(commands, 1, &barrier);
        step = "Submit D3D12 window frame";
        hr = ID3D12GraphicsCommandList_Close(commands); if (FAILED(hr)) goto failed;
        ID3D12CommandList *lists[] = {(ID3D12CommandList *)commands};
        ID3D12CommandQueue_ExecuteCommandLists(queue, 1, lists); *pending = 1;
        hr = ID3D12CommandQueue_Signal(queue, fence, frame + 1); if (FAILED(hr)) goto failed;
        hr = ID3D12Fence_SetEventOnCompletion(fence, frame + 1, event); if (FAILED(hr)) goto failed;
        if (WaitForSingleObject(event, 15000) != WAIT_OBJECT_0) { hr = HRESULT_FROM_WIN32(WAIT_TIMEOUT); goto failed; }
        *pending = 0;
        hr = ID3D12Device_GetDeviceRemovedReason(device); if (FAILED(hr)) goto failed;
        void *mapped = NULL; D3D12_RANGE range = {(SIZE_T)footprint.Offset, (SIZE_T)footprint.Offset + 4};
        hr = ID3D12Resource_Map(readback, 0, &range, &mapped); if (FAILED(hr)) goto failed;
        int pixel_ok = expected_pixel((const unsigned char *)mapped + footprint.Offset);
        D3D12_RANGE no_write = {0, 0}; ID3D12Resource_Unmap(readback, 0, &no_write);
        if (!pixel_ok) { snprintf(detail, detail_size, "The window back-buffer shader pixel did not match on frame %u", frame); goto done; }
        step = "Present D3D12 window frame (occlusion does not count as a pass)";
        hr = IDXGISwapChain3_Present(swap, 1, 0);
        if (hr != S_OK) goto failed;
        *pending = 1; /* Present is queued after the frame's readback fence. */
        ++*presents;
        Sleep(16);
    }
    step = "Wait for final D3D12 presentation";
    *pending = 1;
    hr = ID3D12CommandQueue_Signal(queue, fence, 61); if (FAILED(hr)) goto failed;
    hr = ID3D12Fence_SetEventOnCompletion(fence, 61, event); if (FAILED(hr)) goto failed;
    if (WaitForSingleObject(event, 15000) != WAIT_OBJECT_0) { hr = HRESULT_FROM_WIN32(WAIT_TIMEOUT); goto failed; }
    *pending = 0;
    hr = ID3D12Device_GetDeviceRemovedReason(device); if (FAILED(hr)) goto failed;
    passed = 1;
    snprintf(detail, detail_size, "60 SM 6.0/DXIL shader frames passed back-buffer readback and Present returned S_OK. This verifies API presentation; visual correctness and game compatibility still need testing.");
    goto done;
failed:
    snprintf(detail, detail_size, "%s failed or was unavailable (0x%08lx); %d successful presents", step, (unsigned long)hr, *presents);
done:
    if (*pending) return 0;
    if (event) CloseHandle(event);
    if (fence) ID3D12Fence_Release(fence);
    if (commands) ID3D12GraphicsCommandList_Release(commands);
    if (allocator) ID3D12CommandAllocator_Release(allocator);
    if (views) ID3D12DescriptorHeap_Release(views);
    if (readback) ID3D12Resource_Release(readback);
    for (UINT index = 0; index < 2; ++index) if (buffers[index]) ID3D12Resource_Release(buffers[index]);
    if (swap) IDXGISwapChain3_Release(swap);
    if (swap1) IDXGISwapChain1_Release(swap1);
    if (factory2) IDXGIFactory2_Release(factory2);
    if (window && IsWindow(window)) DestroyWindow(window);
    UnregisterClassA(cls.lpszClassName, cls.hInstance);
    return passed;
}
