// Original diagnostic using separately supplied public NVIDIA Streamline headers.
// Loads the owner's game plugins read-only, disables OTA, and logs support checks.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dxgi1_2.h>
#include <cstdio>
#include <string>
#include "sl.h"

static void message(sl::LogType type, const char *text) {
    std::printf("SL[%u] %s\n", unsigned(type), text);
}
int wmain(int argc, wchar_t **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc != 2) return 10;
    std::wstring directory(argv[1]);
    SetDllDirectoryW(directory.c_str());
    auto module = LoadLibraryExW((directory + L"\\sl.interposer.dll").c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!module) { std::printf("Interposer load failed: %lu\n", GetLastError()); return 11; }
    auto init = reinterpret_cast<PFun_slInit*>(GetProcAddress(module, "slInit"));
    auto supported = reinterpret_cast<PFun_slIsFeatureSupported*>(GetProcAddress(module, "slIsFeatureSupported"));
    auto requirements = reinterpret_cast<PFun_slGetFeatureRequirements*>(GetProcAddress(module, "slGetFeatureRequirements"));
    auto setDevice = reinterpret_cast<PFun_slSetD3DDevice*>(GetProcAddress(module, "slSetD3DDevice"));
    auto shutdown = reinterpret_cast<PFun_slShutdown*>(GetProcAddress(module, "slShutdown"));
    if (!init || !supported || !requirements || !setDevice || !shutdown) return 12;
    sl::Feature features[] = {sl::kFeatureDLSS};
    const wchar_t *paths[] = {directory.c_str()};
    sl::Preferences preferences{};
    preferences.logLevel = sl::LogLevel::eVerbose;
    preferences.logMessageCallback = message;
    preferences.flags = sl::PreferenceFlags::eDisableCLStateTracking | sl::PreferenceFlags::eUseManualHooking;
    preferences.featuresToLoad = features;
    preferences.numFeaturesToLoad = 1;
    preferences.pathsToPlugins = paths;
    preferences.numPathsToPlugins = 1;
    preferences.engineVersion = "GGGMac diagnostic";
    preferences.projectId = "75e0724c-6e7d-4b28-81e9-e4816bc6914e";
    auto result = init(preferences, (uint64_t(2) << 48) | 0xfedc);
    std::printf("slInit: %d\n", int(result));
    if (result != sl::Result::eOk) return 13;
    IDXGIFactory1 *factory = nullptr;
    HRESULT hr = CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory));
    if (FAILED(hr)) return 14;
    IDXGIAdapter1 *adapter = nullptr;
    hr = factory->EnumAdapters1(0, &adapter);
    if (FAILED(hr)) return 15;
    DXGI_ADAPTER_DESC1 desc{};
    adapter->GetDesc1(&desc);
    std::printf("Adapter vendor %04x device %04x\n", desc.VendorId, desc.DeviceId);
    sl::AdapterInfo info{};
    info.deviceLUID = reinterpret_cast<uint8_t*>(&desc.AdapterLuid);
    info.deviceLUIDSizeInBytes = sizeof(desc.AdapterLuid);
    result = supported(sl::kFeatureDLSS, info);
    std::printf("SL DLSS adapter support: %d\n", int(result));
    sl::FeatureRequirements req{};
    auto r = requirements(sl::kFeatureDLSS, req);
    std::printf("SL requirements: %d; OS detected %u.%u.%u required %u.%u.%u; driver detected %u.%u.%u required %u.%u.%u\n",
        int(r), req.osVersionDetected.major, req.osVersionDetected.minor, req.osVersionDetected.build,
        req.osVersionRequired.major, req.osVersionRequired.minor, req.osVersionRequired.build,
        req.driverVersionDetected.major, req.driverVersionDetected.minor, req.driverVersionDetected.build,
        req.driverVersionRequired.major, req.driverVersionRequired.minor, req.driverVersionRequired.build);
    using CreateDevice = HRESULT(WINAPI*)(IUnknown*, unsigned, const GUID*, void**);
    auto d3d = LoadLibraryA("d3d12.dll");
    auto create = d3d ? reinterpret_cast<CreateDevice>(GetProcAddress(d3d, "D3D12CreateDevice")) : nullptr;
    const GUID deviceID = {0x189819f1, 0x1db6, 0x4b57, {0xbe, 0x54, 0x18, 0x21, 0x33, 0x9b, 0x85, 0xf7}};
    IUnknown *device = nullptr;
    hr = create ? create(adapter, 0xb000, &deviceID, reinterpret_cast<void**>(&device)) : E_FAIL;
    std::printf("D3D12 create: %08lx\n", (unsigned long)hr);
    if (device) {
        std::printf("slSetD3DDevice: %d\n", int(setDevice(device)));
        result = supported(sl::kFeatureDLSS, info);
        std::printf("SL DLSS support after device: %d\n", int(result));
    }
    shutdown();
    if (device) device->Release();
    adapter->Release(); factory->Release();
    return result == sl::Result::eOk ? 0 : 16;
}
