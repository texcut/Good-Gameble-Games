/* Original GGGMac bridge diagnostic. No vendor SDK headers or binaries bundled.
 * Checks DLL routing, D3D12 device creation and NGX initialization/capabilities.
 * It does not render an upscaled frame or measure game performance.
 */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <unknwn.h>
#include <stdint.h>
#include <stdio.h>

typedef HRESULT (WINAPI *CreateDevice)(IUnknown *, unsigned, const GUID *, void **);
typedef void *(__cdecl *QueryInterface)(unsigned);
typedef int (__cdecl *InitializeNVAPI)(void);
typedef unsigned (__cdecl *InitializeNGX)(uint64_t, const wchar_t *, void *, unsigned);
typedef unsigned (__cdecl *GetCapabilities)(void **);
typedef unsigned (__cdecl *DestroyParameters)(void *);
typedef unsigned (__cdecl *ShutdownNGX)(void);

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("Loading builtin NVAPI/NGX and D3D12");
    HMODULE nvapi = LoadLibraryA("nvapi64.dll"), ngx = LoadLibraryA("nvngx.dll"), d3d = LoadLibraryA("d3d12.dll");
    if (!nvapi || !ngx || !d3d) { printf("Bridge load failed: %lu\n", GetLastError()); return 1; }
    QueryInterface query = (QueryInterface)GetProcAddress(nvapi, "nvapi_QueryInterface");
    InitializeNVAPI nvinit = query ? (InitializeNVAPI)query(0x0150e828) : NULL;
    InitializeNGX init = (InitializeNGX)GetProcAddress(ngx, "NVSDK_NGX_D3D12_Init");
    GetCapabilities capabilities = (GetCapabilities)GetProcAddress(ngx, "NVSDK_NGX_D3D12_GetCapabilityParameters");
    DestroyParameters destroy = (DestroyParameters)GetProcAddress(ngx, "NVSDK_NGX_D3D12_DestroyParameters");
    ShutdownNGX shutdown = (ShutdownNGX)GetProcAddress(ngx, "NVSDK_NGX_D3D12_Shutdown");
    CreateDevice create = (CreateDevice)GetProcAddress(d3d, "D3D12CreateDevice");
    if (!nvinit || !init || !capabilities || !destroy || !shutdown || !create) { puts("Bridge export missing"); return 2; }
    int nv = nvinit();
    printf("NVAPI initialization: %d\n", nv);
    if (nv != 0) return 3;
    const GUID deviceID = {0x189819f1, 0x1db6, 0x4b57, {0xbe, 0x54, 0x18, 0x21, 0x33, 0x9b, 0x85, 0xf7}};
    IUnknown *device = NULL;
    HRESULT hr = create(NULL, 0xb000, &deviceID, (void **)&device);
    printf("D3D12 device: 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr) || !device) return 4;
    unsigned result = init(0, L"C:\\", device, 0x15);
    printf("NGX initialization: 0x%08x\n", result);
    if (result != 1) { IUnknown_Release(device); return 5; }
    void *parameters = NULL;
    result = capabilities(&parameters);
    printf("NGX capabilities: 0x%08x; parameters present: %s\n", result, parameters ? "yes" : "no");
    int passed = result == 1 && parameters;
    if (parameters) destroy(parameters);
    shutdown();
    IUnknown_Release(device);
    if (passed) puts("GGGMAC_METALFX_BRIDGE_OK");
    return passed ? 0 : 6;
}
