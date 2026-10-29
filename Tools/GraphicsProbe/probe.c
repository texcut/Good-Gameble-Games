/* SPDX-License-Identifier: GPL-3.0-or-later
 * Original GGGMac diagnostic. No game data or graphics driver code is included.
 * Tests offscreen SM 5.0/SM 6.0 shader draws and optional window presentation.
 * Does not establish game compatibility or visual correctness.
 */
#define COBJMACROS
#define WIDL_C_INLINE_WRAPPERS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <GL/gl.h>
#include <stdio.h>
#include <string.h>

static void quoted(const char *s) {
    putchar('"');
    for (const unsigned char *p = (const unsigned char *)(s ? s : ""); *p; ++p) {
        if (*p == '"' || *p == '\\') { putchar('\\'); putchar(*p); }
        else if (*p < 32) printf("\\u%04x", *p);
        else putchar(*p);
    }
    putchar('"');
}
static void report(const char *api, int passed, const char *renderer, const char *version, const char *detail) {
    printf("GGGMAC_GRAPHICS_JSON:{\"api\":"); quoted(api);
    printf(",\"passed\":%s,\"renderer\":", passed ? "true" : "false"); quoted(renderer);
    printf(",\"version\":"); quoted(version);
    printf(",\"detail\":"); quoted(detail);
    puts("}"); fflush(stdout);
}
static int expected_pixel(const unsigned char *p) {
    return p[0] >= 63 && p[0] <= 65 && p[1] >= 127 && p[1] <= 129 && p[2] >= 190 && p[2] <= 192;
}
#include "d3d12_probe.h"
static int gl_readback(void) {
    glViewport(0, 0, 4, 4); glClearColor(0.25f, 0.5f, 0.75f, 1.0f); glClear(GL_COLOR_BUFFER_BIT);
    unsigned char pixel[4] = {0};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    return glGetError() == GL_NO_ERROR && expected_pixel(pixel);
}

static void check_d3d11(void) {
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    ID3D11Texture2D *texture = NULL, *staging = NULL;
    ID3D11RenderTargetView *view = NULL;
    IDXGIDevice *dxgi = NULL;
    IDXGIAdapter *adapter = NULL;
    D3D_FEATURE_LEVEL level = 0;
    const D3D_FEATURE_LEVEL requested[] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0 };
    char renderer[512] = "", version[32] = "", detail[128] = "";
    int passed = 0;
    typedef HRESULT (WINAPI *CreateDevice)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
        const D3D_FEATURE_LEVEL *, UINT, UINT, ID3D11Device **, D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);
    HMODULE module = LoadLibraryA("d3d11.dll");
    CreateDevice create = module ? (CreateDevice)GetProcAddress(module, "D3D11CreateDevice") : NULL;
    if (!create) { strcpy(detail, "The D3D11 device creation entry point is unavailable"); goto done; }
    HRESULT hr = create(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, requested, 3,
        D3D11_SDK_VERSION, &device, &level, &context);
    if (FAILED(hr)) { snprintf(detail, sizeof(detail), "Hardware device creation failed (0x%08lx)", (unsigned long)hr); goto done; }
    snprintf(version, sizeof(version), "%u.%u", (unsigned)level >> 12, ((unsigned)level >> 8) & 15);
    if (SUCCEEDED(ID3D11Device_QueryInterface(device, &IID_IDXGIDevice, (void **)&dxgi)) &&
        SUCCEEDED(IDXGIDevice_GetAdapter(dxgi, &adapter))) {
        DXGI_ADAPTER_DESC desc;
        if (SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc)))
            WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, renderer, sizeof(renderer), NULL, NULL);
    }
    D3D11_TEXTURE2D_DESC desc = {0};
    desc.Width = 4; desc.Height = 4; desc.MipLevels = 1; desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM; desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT; desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    hr = ID3D11Device_CreateTexture2D(device, &desc, NULL, &texture);
    if (FAILED(hr)) goto failed;
    hr = ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)texture, NULL, &view);
    if (FAILED(hr)) goto failed;
    const FLOAT color[] = {0.25f, 0.5f, 0.75f, 1.0f};
    ID3D11DeviceContext_ClearRenderTargetView(context, view, color);
    desc.Usage = D3D11_USAGE_STAGING; desc.BindFlags = 0; desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = ID3D11Device_CreateTexture2D(device, &desc, NULL, &staging);
    if (FAILED(hr)) goto failed;
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging, (ID3D11Resource *)texture);
    D3D11_MAPPED_SUBRESOURCE mapped;
    hr = ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped);
    if (FAILED(hr)) goto failed;
    passed = expected_pixel((unsigned char *)mapped.pData) && !strstr(renderer, "llvmpipe") && !strstr(renderer, "softpipe");
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
    snprintf(detail, sizeof(detail), "%s", passed ? "Hardware device, texture clear and pixel readback passed" : "Pixel readback did not match the expected color");
    goto done;
failed:
    snprintf(detail, sizeof(detail), "Texture operation failed (0x%08lx)", (unsigned long)hr);
done:
    if (view) ID3D11RenderTargetView_Release(view);
    if (staging) ID3D11Texture2D_Release(staging);
    if (texture) ID3D11Texture2D_Release(texture);
    if (adapter) IDXGIAdapter_Release(adapter);
    if (dxgi) IDXGIDevice_Release(dxgi);
    if (context) ID3D11DeviceContext_Release(context);
    if (device) ID3D11Device_Release(device);
    if (module) FreeLibrary(module);
    report("d3d11", passed, renderer, version, detail);
}

typedef HGLRC (WINAPI *CreateContextAttributes)(HDC, HGLRC, const int *);
static void check_opengl(void) {
    HWND window = CreateWindowA("STATIC", "GGGMac GPU diagnostic", WS_POPUP, 0, 0, 16, 16, NULL, NULL, GetModuleHandle(NULL), NULL);
    HDC dc = window ? GetDC(window) : NULL;
    HGLRC legacy = NULL, core = NULL;
    char renderer[512] = "", version[128] = "", detail[128] = "";
    int passed = 0;
    if (!dc) { strcpy(detail, "Could not create a hidden Windows drawing surface"); goto done; }
    PIXELFORMATDESCRIPTOR format = {0};
    format.nSize = sizeof(format); format.nVersion = 1;
    format.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    format.iPixelType = PFD_TYPE_RGBA; format.cColorBits = 24;
    int index = ChoosePixelFormat(dc, &format);
    if (!index || !SetPixelFormat(dc, index, &format)) { strcpy(detail, "No OpenGL pixel format"); goto done; }
    legacy = wglCreateContext(dc);
    if (!legacy || !wglMakeCurrent(dc, legacy)) { strcpy(detail, "Could not create an OpenGL context"); goto done; }
    snprintf(renderer, sizeof(renderer), "%s", glGetString(GL_RENDERER) ? (const char *)glGetString(GL_RENDERER) : "");
    snprintf(version, sizeof(version), "%s", glGetString(GL_VERSION) ? (const char *)glGetString(GL_VERSION) : "");
    CreateContextAttributes create = (CreateContextAttributes)wglGetProcAddress("wglCreateContextAttribsARB");
    if (!create) { strcpy(detail, "OpenGL 3.2 core context creation is unavailable"); goto done; }
    const int attributes[] = {0x2091, 3, 0x2092, 2, 0x9126, 1, 0};
    core = create(dc, NULL, attributes);
    if (!core || !wglMakeCurrent(dc, core)) {
        if (core) wglDeleteContext(core);
        const int forward[] = {0x2091, 3, 0x2092, 2, 0x2094, 2, 0x9126, 1, 0};
        core = create(dc, NULL, forward);
        if (core && wglMakeCurrent(dc, core) && gl_readback())
            strcpy(detail, "Standard OpenGL 3.2 request rejected. Forward-compatible request passed GPU readback; an app/runtime context fix is needed.");
        else strcpy(detail, "The driver rejected an OpenGL 3.2 core context");
        goto done;
    }
    snprintf(renderer, sizeof(renderer), "%s", (const char *)glGetString(GL_RENDERER));
    snprintf(version, sizeof(version), "%s", (const char *)glGetString(GL_VERSION));
    passed = gl_readback() &&
        !strstr(renderer, "llvmpipe") && !strstr(renderer, "softpipe");
    snprintf(detail, sizeof(detail), "%s", passed ? "OpenGL 3.2 core context and pixel readback passed" : "OpenGL readback failed or reported a software renderer");
done:
    wglMakeCurrent(NULL, NULL);
    if (core) wglDeleteContext(core);
    if (legacy) wglDeleteContext(legacy);
    if (dc) ReleaseDC(window, dc);
    if (window) DestroyWindow(window);
    report("opengl", passed, renderer, version, detail);
}

int main(int argc, char **argv) {
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
    if (argc != 2) return 2;
    if (!strcmp(argv[1], "opengl")) check_opengl();
    else if (!strcmp(argv[1], "d3d11")) check_d3d11();
    else if (!strcmp(argv[1], "d3d12")) check_d3d12(0);
    else if (!strcmp(argv[1], "d3d12-dxil")) check_d3d12(1);
    else if (!strcmp(argv[1], "d3d12-present")) check_d3d12(2);
    else return 2;
    return 0; /* Capability failure is reported as JSON, not a crashed process. */
}
