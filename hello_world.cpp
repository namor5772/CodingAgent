// Minimal Win32 clone of hello_world.py — window titled "Hello World"
// showing centered HELLO WORLD on a dark background, with optional .ico.

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>
#include <string>

namespace {

constexpr int kDefaultWidth = 400;
constexpr int kDefaultHeight = 200;
constexpr int kMinWidth = 300;
constexpr int kMinHeight = 150;

// Match hello_world.py: bg #1a1a2e, fg #eaeaea
constexpr COLORREF kBgColor = RGB(0x1a, 0x1a, 0x2e);
constexpr COLORREF kFgColor = RGB(0xea, 0xea, 0xea);

const wchar_t kWindowClass[] = L"CodingAgentHelloWorldWindow";
const wchar_t kWindowTitle[] = L"Hello World";
const wchar_t kLabelText[] = L"HELLO WORLD";

HBRUSH g_bgBrush = nullptr;
HFONT g_labelFont = nullptr;
HICON g_iconBig = nullptr;
HICON g_iconSmall = nullptr;

std::wstring ExeDirectory() {
    wchar_t path[MAX_PATH] = {};
    const DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) {
        return L".";
    }
    std::wstring full(path, n);
    const size_t slash = full.find_last_of(L"\\/");
    if (slash == std::wstring::npos) {
        return L".";
    }
    return full.substr(0, slash);
}

void TryLoadIcons(HINSTANCE instance) {
    const std::wstring icoPath = ExeDirectory() + L"\\hello_world.ico";
    // LoadImage with LR_LOADFROMFILE for the bundled multi-size ICO.
    g_iconBig = static_cast<HICON>(LoadImageW(
        nullptr,
        icoPath.c_str(),
        IMAGE_ICON,
        GetSystemMetrics(SM_CXICON),
        GetSystemMetrics(SM_CYICON),
        LR_LOADFROMFILE | LR_DEFAULTCOLOR));
    g_iconSmall = static_cast<HICON>(LoadImageW(
        nullptr,
        icoPath.c_str(),
        IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON),
        GetSystemMetrics(SM_CYSMICON),
        LR_LOADFROMFILE | LR_DEFAULTCOLOR));

    // Fall back to the executable's own icon resource if the .ico is missing.
    if (!g_iconBig) {
        g_iconBig = LoadIconW(instance, MAKEINTRESOURCEW(1));
    }
    if (!g_iconSmall) {
        g_iconSmall = g_iconBig;
    }
}

void DrawHello(HWND hwnd, HDC hdc) {
    RECT client = {};
    GetClientRect(hwnd, &client);

    FillRect(hdc, &client, g_bgBrush);

    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, kFgColor);
    HGDIOBJ oldFont = SelectObject(hdc, g_labelFont);

    DrawTextW(
        hdc,
        kLabelText,
        -1,
        &client,
        DT_SINGLELINE | DT_CENTER | DT_VCENTER | DT_NOPREFIX);

    SelectObject(hdc, oldFont);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE: {
        // Segoe UI 32pt bold — same face/size intent as the Tk label.
        // CreateFont height is in logical pixels; -pt * dpi/72.
        const HDC screen = GetDC(nullptr);
        const int dpi = GetDeviceCaps(screen, LOGPIXELSY);
        ReleaseDC(nullptr, screen);
        const int height = -MulDiv(32, dpi, 72);
        g_labelFont = CreateFontW(
            height,
            0,
            0,
            0,
            FW_BOLD,
            FALSE,
            FALSE,
            FALSE,
            DEFAULT_CHARSET,
            OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY,
            DEFAULT_PITCH | FF_SWISS,
            L"Segoe UI");
        return 0;
    }

    case WM_GETMINMAXINFO: {
        auto* info = reinterpret_cast<MINMAXINFO*>(lParam);
        // minsize applies to the outer window (including non-client frame),
        // matching Tk's root.minsize on the window as a whole.
        info->ptMinTrackSize.x = kMinWidth;
        info->ptMinTrackSize.y = kMinHeight;
        return 0;
    }

    case WM_ERASEBKGND:
        // Painted fully in WM_PAINT; skip default erase to avoid flicker.
        return 1;

    case WM_PAINT: {
        PAINTSTRUCT ps = {};
        HDC hdc = BeginPaint(hwnd, &ps);
        DrawHello(hwnd, hdc);
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_DESTROY:
        if (g_labelFont) {
            DeleteObject(g_labelFont);
            g_labelFont = nullptr;
        }
        PostQuitMessage(0);
        return 0;

    default:
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR, int showCmd) {
    g_bgBrush = CreateSolidBrush(kBgColor);
    TryLoadIcons(instance);

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = g_bgBrush;
    wc.lpszClassName = kWindowClass;
    wc.hIcon = g_iconBig ? g_iconBig : LoadIconW(nullptr, IDI_APPLICATION);
    wc.hIconSm = g_iconSmall ? g_iconSmall : wc.hIcon;

    if (!RegisterClassExW(&wc)) {
        return 1;
    }

    // Center the default 400x200 window on the work area.
    RECT work = {};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    const int x = work.left + ((work.right - work.left) - kDefaultWidth) / 2;
    const int y = work.top + ((work.bottom - work.top) - kDefaultHeight) / 2;

    HWND hwnd = CreateWindowExW(
        0,
        kWindowClass,
        kWindowTitle,
        WS_OVERLAPPEDWINDOW,
        x,
        y,
        kDefaultWidth,
        kDefaultHeight,
        nullptr,
        nullptr,
        instance,
        nullptr);

    if (!hwnd) {
        return 1;
    }

    if (g_iconBig) {
        SendMessageW(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(g_iconBig));
    }
    if (g_iconSmall) {
        SendMessageW(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(g_iconSmall));
    }

    ShowWindow(hwnd, showCmd);
    UpdateWindow(hwnd);

    MSG msg = {};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    // Icons from LoadImage(LR_LOADFROMFILE) must be DestroyIcon'd once each.
    if (g_iconSmall && g_iconSmall != g_iconBig) {
        DestroyIcon(g_iconSmall);
    }
    g_iconSmall = nullptr;
    if (g_iconBig) {
        DestroyIcon(g_iconBig);
    }
    g_iconBig = nullptr;
    if (g_bgBrush) {
        DeleteObject(g_bgBrush);
        g_bgBrush = nullptr;
    }

    return static_cast<int>(msg.wParam);
}
