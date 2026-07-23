// Win32 clone of hello_world.py — stick figure with a hat walking
// across a dark window (title/colors/minsize/icon matched).

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>
#include <cmath>
#include <string>

namespace {

constexpr int kDefaultWidth = 400;
constexpr int kDefaultHeight = 200;
constexpr int kMinWidth = 300;
constexpr int kMinHeight = 150;

// Match hello_world.py: bg #1a1a2e, fg #eaeaea, hat #c9a227
constexpr COLORREF kBgColor = RGB(0x1a, 0x1a, 0x2e);
constexpr COLORREF kFgColor = RGB(0xea, 0xea, 0xea);
constexpr COLORREF kHatColor = RGB(0xc9, 0xa2, 0x27);
constexpr COLORREF kGroundColor = RGB(0x2a, 0x2a, 0x44);

constexpr UINT kTimerId = 1;
constexpr UINT kFrameMs = 50;
constexpr double kWalkSpeed = 2.4;
constexpr double kTau = 6.28318530717958647692;

const wchar_t kWindowClass[] = L"CodingAgentHelloWorldWindow";
const wchar_t kWindowTitle[] = L"Hello World";

HBRUSH g_bgBrush = nullptr;
HICON g_iconBig = nullptr;
HICON g_iconSmall = nullptr;

double g_phase = 0.0;
double g_x = 40.0;

struct Pose {
    double leg_l;
    double leg_r;
    double knee_l;
    double knee_r;
    double arm_l;
    double arm_r;
    double bob;
};

Pose WalkPose(double phase) {
    const double swing = std::sin(phase * kTau);
    const double other = std::sin(phase * kTau + 3.14159265358979323846);
    Pose p{};
    p.leg_l = 0.48 * swing;
    p.leg_r = 0.48 * other;
    p.knee_l = 0.55 * (swing < 0.0 ? -swing : 0.0);
    p.knee_r = 0.55 * (other < 0.0 ? -other : 0.0);
    p.arm_l = 0.40 * other;
    p.arm_r = 0.40 * swing;
    p.bob = 2.0 * std::abs(std::sin(phase * kTau * 2.0));
    return p;
}

void LimbEnd(double x, double y, double angle, double length, double* ox, double* oy) {
    // angle 0 = straight down; positive = clockwise (screen y grows downward).
    *ox = x + length * std::sin(angle);
    *oy = y + length * std::cos(angle);
}

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

    if (!g_iconBig) {
        g_iconBig = LoadIconW(instance, MAKEINTRESOURCEW(1));
    }
    if (!g_iconSmall) {
        g_iconSmall = g_iconBig;
    }
}

HPEN MakePen(COLORREF color, int width) {
    // Match Tk capstyle=ROUND: geometric pen with round caps/joins (gdi32 only).
    const int w = width > 0 ? width : 1;
    LOGBRUSH brush = {};
    brush.lbStyle = BS_SOLID;
    brush.lbColor = color;
    HPEN pen = ExtCreatePen(
        PS_GEOMETRIC | PS_SOLID | PS_ENDCAP_ROUND | PS_JOIN_ROUND,
        w,
        &brush,
        0,
        nullptr);
    if (pen) {
        return pen;
    }
    return CreatePen(PS_SOLID, w, color);
}

// Convert desired client size to outer (non-client included) size for WS styles.
bool ClientSizeToOuter(DWORD style, DWORD exStyle, int clientW, int clientH,
                       int* outerW, int* outerH) {
    RECT rc = {0, 0, clientW, clientH};
    if (!AdjustWindowRectEx(&rc, style, FALSE, exStyle)) {
        return false;
    }
    *outerW = rc.right - rc.left;
    *outerH = rc.bottom - rc.top;
    return true;
}

void CleanupGlobals() {
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
}

void LineTo2(HDC hdc, int x1, int y1, int x2, int y2) {
    MoveToEx(hdc, x1, y1, nullptr);
    LineTo(hdc, x2, y2);
}

void DrawWalker(HWND hwnd, HDC hdc) {
    RECT client = {};
    GetClientRect(hwnd, &client);
    const int w = client.right - client.left;
    const int h = client.bottom - client.top;
    if (w <= 0 || h <= 0) {
        return;
    }

    FillRect(hdc, &client, g_bgBrush);

    const double scale = (std::max)(0.55, (std::min)(w / 400.0, h / 200.0));
    const Pose pose = WalkPose(g_phase);
    const double cx = g_x;
    const double cy = h * 0.55 + pose.bob * scale;

    const double head_r = 12.0 * scale;
    const double torso = 34.0 * scale;
    const double upper_leg = 22.0 * scale;
    const double lower_leg = 20.0 * scale;
    const double upper_arm = 16.0 * scale;
    const double lower_arm = 14.0 * scale;
    const int stroke = (std::max)(2, static_cast<int>(std::lround(3.0 * scale)));

    const double hip_y = cy + torso;
    const double shoulder_y = cy + 8.0 * scale;
    const double head_cx = cx;
    const double head_cy = cy - head_r - 2.0 * scale;

    // Ground line
    const double ground_y = hip_y + upper_leg + lower_leg + 4.0 * scale;
    HPEN groundPen = MakePen(kGroundColor, (std::max)(1, stroke - 1));
    HGDIOBJ oldPen = SelectObject(hdc, groundPen);
    LineTo2(hdc, 0, static_cast<int>(std::lround(ground_y)), w,
            static_cast<int>(std::lround(ground_y)));
    SelectObject(hdc, oldPen);
    DeleteObject(groundPen);

    HPEN fgPen = MakePen(kFgColor, stroke);
    oldPen = SelectObject(hdc, fgPen);
    HGDIOBJ oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH));

    // Torso
    LineTo2(hdc, static_cast<int>(std::lround(cx)), static_cast<int>(std::lround(cy)),
            static_cast<int>(std::lround(cx)), static_cast<int>(std::lround(hip_y)));

    // Head
    Ellipse(hdc,
            static_cast<int>(std::lround(head_cx - head_r)),
            static_cast<int>(std::lround(head_cy - head_r)),
            static_cast<int>(std::lround(head_cx + head_r)),
            static_cast<int>(std::lround(head_cy + head_r)));

    SelectObject(hdc, oldBrush);
    SelectObject(hdc, oldPen);
    DeleteObject(fgPen);

    // Hat: brim + crown (before limbs — match hello_world.py draw order)
    HPEN hatPen = MakePen(kHatColor, stroke);
    oldPen = SelectObject(hdc, hatPen);
    oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH));

    const double brim_w = head_r * 1.7;
    const double brim_y = head_cy - head_r * 0.55;
    LineTo2(hdc, static_cast<int>(std::lround(head_cx - brim_w)),
            static_cast<int>(std::lround(brim_y)),
            static_cast<int>(std::lround(head_cx + brim_w)),
            static_cast<int>(std::lround(brim_y)));

    const double crown_w = head_r * 1.05;
    const double crown_h = head_r * 1.15;
    Rectangle(hdc,
              static_cast<int>(std::lround(head_cx - crown_w)),
              static_cast<int>(std::lround(brim_y - crown_h)),
              static_cast<int>(std::lround(head_cx + crown_w)),
              static_cast<int>(std::lround(brim_y)));

    SelectObject(hdc, oldBrush);
    SelectObject(hdc, oldPen);
    DeleteObject(hatPen);

    fgPen = MakePen(kFgColor, stroke);
    oldPen = SelectObject(hdc, fgPen);

    // Arms
    const double armAngles[2] = {pose.arm_l, pose.arm_r};
    for (double ang : armAngles) {
        double ex = 0, ey = 0, hx = 0, hy = 0;
        LimbEnd(cx, shoulder_y, ang, upper_arm, &ex, &ey);
        LimbEnd(ex, ey, ang + 0.25, lower_arm, &hx, &hy);
        LineTo2(hdc, static_cast<int>(std::lround(cx)), static_cast<int>(std::lround(shoulder_y)),
                static_cast<int>(std::lround(ex)), static_cast<int>(std::lround(ey)));
        LineTo2(hdc, static_cast<int>(std::lround(ex)), static_cast<int>(std::lround(ey)),
                static_cast<int>(std::lround(hx)), static_cast<int>(std::lround(hy)));
    }

    // Legs
    const double legAngles[2] = {pose.leg_l, pose.leg_r};
    const double knees[2] = {pose.knee_l, pose.knee_r};
    for (int i = 0; i < 2; ++i) {
        double kx = 0, ky = 0, fx = 0, fy = 0;
        LimbEnd(cx, hip_y, legAngles[i], upper_leg, &kx, &ky);
        LimbEnd(kx, ky, legAngles[i] + knees[i], lower_leg, &fx, &fy);
        LineTo2(hdc, static_cast<int>(std::lround(cx)), static_cast<int>(std::lround(hip_y)),
                static_cast<int>(std::lround(kx)), static_cast<int>(std::lround(ky)));
        LineTo2(hdc, static_cast<int>(std::lround(kx)), static_cast<int>(std::lround(ky)),
                static_cast<int>(std::lround(fx)), static_cast<int>(std::lround(fy)));
    }

    SelectObject(hdc, oldPen);
    DeleteObject(fgPen);
}

void AdvanceAnimation(HWND hwnd) {
    RECT client = {};
    GetClientRect(hwnd, &client);
    const int w = (std::max)(1L, client.right - client.left);

    g_phase = g_phase + 0.045;
    if (g_phase >= 1.0) {
        g_phase -= 1.0;
    }
    const double speed = kWalkSpeed * (std::max)(w / 400.0, 0.75);
    g_x += speed;
    if (g_x > w + 40.0) {
        g_x = -40.0;
    }
    InvalidateRect(hwnd, nullptr, FALSE);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE:
        SetTimer(hwnd, kTimerId, kFrameMs, nullptr);
        return 0;

    case WM_TIMER:
        if (wParam == kTimerId) {
            AdvanceAnimation(hwnd);
        }
        return 0;

    case WM_GETMINMAXINFO: {
        auto* info = reinterpret_cast<MINMAXINFO*>(lParam);
        // ptMinTrackSize is outer size; convert from desired min client (match Tk minsize).
        const DWORD style = static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_STYLE));
        const DWORD exStyle = static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_EXSTYLE));
        int outerW = kMinWidth;
        int outerH = kMinHeight;
        if (ClientSizeToOuter(style, exStyle, kMinWidth, kMinHeight, &outerW, &outerH)) {
            info->ptMinTrackSize.x = outerW;
            info->ptMinTrackSize.y = outerH;
        } else {
            info->ptMinTrackSize.x = kMinWidth;
            info->ptMinTrackSize.y = kMinHeight;
        }
        return 0;
    }

    case WM_ERASEBKGND:
        // Painted fully in WM_PAINT; skip default erase to avoid flicker.
        return 1;

    case WM_PAINT: {
        PAINTSTRUCT ps = {};
        HDC hdc = BeginPaint(hwnd, &ps);

        // Double-buffer to reduce flicker while animating.
        RECT client = {};
        GetClientRect(hwnd, &client);
        const int w = client.right - client.left;
        const int h = client.bottom - client.top;
        if (w <= 0 || h <= 0) {
            EndPaint(hwnd, &ps);
            return 0;
        }

        HDC memDC = CreateCompatibleDC(hdc);
        HBITMAP memBmp = memDC ? CreateCompatibleBitmap(hdc, w, h) : nullptr;
        if (!memDC || !memBmp) {
            // Fallback: draw directly on the paint DC if offscreen buffer fails.
            if (memBmp) {
                DeleteObject(memBmp);
            }
            if (memDC) {
                DeleteDC(memDC);
            }
            DrawWalker(hwnd, hdc);
            EndPaint(hwnd, &ps);
            return 0;
        }

        HGDIOBJ oldBmp = SelectObject(memDC, memBmp);
        DrawWalker(hwnd, memDC);
        BitBlt(hdc, 0, 0, w, h, memDC, 0, 0, SRCCOPY);

        SelectObject(memDC, oldBmp);
        DeleteObject(memBmp);
        DeleteDC(memDC);

        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_DESTROY:
        KillTimer(hwnd, kTimerId);
        PostQuitMessage(0);
        return 0;

    default:
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR, int showCmd) {
    g_bgBrush = CreateSolidBrush(kBgColor);
    if (!g_bgBrush) {
        return 1;
    }
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
        CleanupGlobals();
        return 1;
    }

    constexpr DWORD kWindowStyle = WS_OVERLAPPEDWINDOW;
    constexpr DWORD kWindowExStyle = 0;

    // CreateWindowEx width/height are outer; request client 400x200 to match Tk geometry.
    int outerW = kDefaultWidth;
    int outerH = kDefaultHeight;
    if (!ClientSizeToOuter(kWindowStyle, kWindowExStyle, kDefaultWidth, kDefaultHeight,
                           &outerW, &outerH)) {
        CleanupGlobals();
        return 1;
    }

    RECT work = {};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    const int x = work.left + ((work.right - work.left) - outerW) / 2;
    const int y = work.top + ((work.bottom - work.top) - outerH) / 2;

    HWND hwnd = CreateWindowExW(
        kWindowExStyle,
        kWindowClass,
        kWindowTitle,
        kWindowStyle,
        x,
        y,
        outerW,
        outerH,
        nullptr,
        nullptr,
        instance,
        nullptr);

    if (!hwnd) {
        CleanupGlobals();
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

    CleanupGlobals();

    return static_cast<int>(msg.wParam);
}
