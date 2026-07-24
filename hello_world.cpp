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
#include <cstdio>
#include <cstring>
#include <string>

namespace {

constexpr int kDefaultWidth = 400;
constexpr int kDefaultHeight = 200;
constexpr int kMinWidth = 300;
constexpr int kMinHeight = 150;

// Client size + outer top-left position (same fields as the Python JSON config).
struct WindowGeometry {
    int x = 0;
    int y = 0;
    int w = kDefaultWidth;
    int h = kDefaultHeight;
    bool valid = false;
};

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
    double foot_l;
    double foot_r;
    double arm_l;
    double arm_r;
    double bob;
};

Pose WalkPose(double phase) {
    // Mirror of hello_world.py walk_pose: heel strike with a straight knee,
    // near-straight stance, then heel lift + knee flexion through the forward
    // swing. Knee flexion is one-signed (shin folds backward only) and is
    // drawn as hip_angle - knee.
    const double kPi = 3.14159265358979323846;
    const double t = phase * kTau;
    Pose p{};
    p.leg_l = 0.45 * std::sin(t);
    p.leg_r = 0.45 * std::sin(t + kPi);
    // cos(t + lead) > 0 from late stance through the forward swing; the 0.6
    // lead starts the heel lift just before toe-off and peaks mid-recovery.
    const double flex_l = std::cos(t + 0.6);
    const double flex_r = std::cos(t + kPi + 0.6);
    p.knee_l = 1.0 * (flex_l > 0.0 ? flex_l : 0.0);
    p.knee_r = 1.0 * (flex_r > 0.0 ? flex_r : 0.0);
    // Feet (pi/2 = flat on the ground, toes forward): dorsiflex (toes up)
    // into heel strike, rock flat by mid-stance, then plantarflex (heel up,
    // toes down) through toe-off into early swing — knee flexion gated to
    // the leg being behind the body is exactly the heel-lift window.
    const double sin_l = std::sin(t);
    const double sin_r = std::sin(t + kPi);
    p.foot_l = kPi / 2.0 + 0.4 * (sin_l > 0.0 ? sin_l : 0.0) -
               0.8 * p.knee_l * (sin_l < 0.0 ? -sin_l : 0.0);
    p.foot_r = kPi / 2.0 + 0.4 * (sin_r > 0.0 ? sin_r : 0.0) -
               0.8 * p.knee_r * (sin_r < 0.0 ? -sin_r : 0.0);
    p.arm_l = 0.40 * std::sin(t + kPi);  // arms counter same-side legs
    p.arm_r = 0.40 * std::sin(t);
    // One bounce per step: 4.2 = 42 * (1 - cos(0.45)) keeps the straight
    // leg's foot on the ground line at both stride extremes (scale 1).
    p.bob = 4.2 * std::abs(std::sin(t));
    return p;
}

struct DogPose {
    double pair_a;
    double pair_b;
    double fold_a;
    double fold_b;
    double tail;
    double bob;
};

DogPose DogTrotPose(double phase) {
    // Mirror of hello_world.py dog_pose: trot with diagonal leg pairs 180 deg
    // apart at the walker's cadence, offset so it is not step-synced with the
    // man. Folds are one-signed (lower leg drawn at angle - fold).
    const double kPi = 3.14159265358979323846;
    const double t = phase * kTau + 1.9;
    DogPose p{};
    p.pair_a = 0.60 * std::sin(t);        // front-left + rear-right
    p.pair_b = 0.60 * std::sin(t + kPi);  // front-right + rear-left
    const double fa = std::cos(t + 0.6);
    const double fb = std::cos(t + kPi + 0.6);
    p.fold_a = 0.9 * (fa > 0.0 ? fa : 0.0);
    p.fold_b = 0.9 * (fb > 0.0 ? fb : 0.0);
    p.tail = 0.25 * std::sin(t * 2.0);  // wag, twice per stride
    // 3.3 = 19 * (1 - cos(0.6)): straight-pair paws stay on the ground line.
    p.bob = 3.3 * std::abs(std::sin(t));
    return p;
}

double ViewScale(double w, double h) {
    // Figure scale for a client size: 400x200 baseline, floor 0.55.
    return (std::max)(0.55, (std::min)(w / 400.0, h / 200.0));
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

// %LOCALAPPDATA%\CodingAgent\hello_world_cpp_geometry.json (C++ only; Python uses
// hello_world_geometry.json in the same folder so each app keeps its own size/pos).
std::wstring GeometryConfigPath() {
    wchar_t dir[MAX_PATH] = {};
    const DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", dir, MAX_PATH);
    std::wstring base;
    if (n > 0 && n < MAX_PATH) {
        base.assign(dir, n);
    } else {
        wchar_t profile[MAX_PATH] = {};
        const DWORD np = GetEnvironmentVariableW(L"USERPROFILE", profile, MAX_PATH);
        if (np > 0 && np < MAX_PATH) {
            base.assign(profile, np);
            base += L"\\AppData\\Local";
        } else {
            base = L".";
        }
    }
    return base + L"\\CodingAgent\\hello_world_cpp_geometry.json";
}

bool EnsureParentDirectory(const std::wstring& filePath) {
    const size_t slash = filePath.find_last_of(L"\\/");
    if (slash == std::wstring::npos) {
        return true;
    }
    const std::wstring dir = filePath.substr(0, slash);
    if (dir.empty()) {
        return true;
    }
    // CreateDirectoryW fails with ERROR_ALREADY_EXISTS if present — that is fine.
    if (CreateDirectoryW(dir.c_str(), nullptr)) {
        return true;
    }
    const DWORD err = GetLastError();
    return err == ERROR_ALREADY_EXISTS;
}

WindowGeometry LoadGeometry() {
    WindowGeometry g{};
    const std::wstring path = GeometryConfigPath();
    FILE* fp = nullptr;
    if (_wfopen_s(&fp, path.c_str(), L"rb") != 0 || !fp) {
        return g;
    }
    char buf[512] = {};
    const size_t n = fread(buf, 1, sizeof(buf) - 1, fp);
    fclose(fp);
    if (n == 0) {
        return g;
    }
    buf[n] = '\0';

    int x = 0, y = 0, w = 0, h = 0;
    // Minimal JSON field scan — matches the Python writer keys.
    const char* px = strstr(buf, "\"x\"");
    const char* py = strstr(buf, "\"y\"");
    const char* pw = strstr(buf, "\"w\"");
    const char* ph = strstr(buf, "\"h\"");
    if (!px || !py || !pw || !ph) {
        return g;
    }
    if (sscanf_s(px, "\"x\"%*[^0-9-]%d", &x) != 1) {
        return g;
    }
    if (sscanf_s(py, "\"y\"%*[^0-9-]%d", &y) != 1) {
        return g;
    }
    if (sscanf_s(pw, "\"w\"%*[^0-9-]%d", &w) != 1) {
        return g;
    }
    if (sscanf_s(ph, "\"h\"%*[^0-9-]%d", &h) != 1) {
        return g;
    }
    if (w < kMinWidth || h < kMinHeight || w > 20000 || h > 20000) {
        return g;
    }
    if (x < -100000 || x > 100000 || y < -100000 || y > 100000) {
        return g;
    }
    g.x = x;
    g.y = y;
    g.w = w;
    g.h = h;
    g.valid = true;
    return g;
}

void SaveGeometry(const WindowGeometry& g) {
    if (g.w < kMinWidth || g.h < kMinHeight) {
        return;
    }
    const std::wstring path = GeometryConfigPath();
    if (!EnsureParentDirectory(path)) {
        return;
    }
    FILE* fp = nullptr;
    if (_wfopen_s(&fp, path.c_str(), L"wb") != 0 || !fp) {
        return;
    }
    std::fprintf(fp,
                 "{\n  \"x\": %d,\n  \"y\": %d,\n  \"w\": %d,\n  \"h\": %d\n}\n",
                 g.x, g.y, g.w, g.h);
    fclose(fp);
}

void SaveGeometryFromHwnd(HWND hwnd) {
    RECT wr = {};
    RECT cr = {};
    if (!GetWindowRect(hwnd, &wr) || !GetClientRect(hwnd, &cr)) {
        return;
    }
    // Skip save while minimized — coords are not useful.
    if (IsIconic(hwnd)) {
        return;
    }
    WindowGeometry g{};
    g.x = wr.left;
    g.y = wr.top;
    g.w = cr.right - cr.left;
    g.h = cr.bottom - cr.top;
    // If maximized, still persist the restored size would be nicer, but matching
    // Python (current outer frame) is enough for this demo.
    if (g.w < kMinWidth) {
        g.w = kMinWidth;
    }
    if (g.h < kMinHeight) {
        g.h = kMinHeight;
    }
    g.valid = true;
    SaveGeometry(g);
}

bool GeometryOnScreen(int outerX, int outerY, int /*outerW*/, int /*outerH*/) {
    // Require the window's top-left (with a small inset) to land on some monitor.
    const POINT pt = {outerX + 20, outerY + 20};
    return MonitorFromPoint(pt, MONITOR_DEFAULTTONULL) != nullptr;
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

    const double scale = ViewScale(w, h);
    const Pose pose = WalkPose(g_phase);
    const double cx = g_x;
    const double base_cy = h * 0.55;  // un-bobbed body reference; anchors the ground
    const double cy = base_cy + pose.bob * scale;

    const double head_r = 12.0 * scale;
    const double torso = 34.0 * scale;
    const double upper_leg = 22.0 * scale;
    const double lower_leg = 20.0 * scale;
    const double foot_len = 8.0 * scale;
    const double upper_arm = 16.0 * scale;
    const double lower_arm = 14.0 * scale;
    const int stroke = (std::max)(2, static_cast<int>(std::lround(3.0 * scale)));

    const double hip_y = cy + torso;
    const double shoulder_y = cy + 8.0 * scale;
    const double head_cx = cx;
    const double head_cy = cy - head_r - 2.0 * scale;

    // Ground line: anchored to the un-bobbed pose (does not bounce with the
    // body) at exactly straight-leg reach, so planted feet touch it.
    const double ground_y = base_cy + torso + upper_leg + lower_leg;
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

    // Face (right profile, facing the walking direction): eye dot, nose
    // wedge poking past the head outline, short mouth line.
    {
        const int face_w = (std::max)(1, stroke - 1);
        const double eye_r = (std::max)(1.2, head_r * 0.12);
        const double eye_x = head_cx + head_r * 0.38;
        const double eye_y = head_cy - head_r * 0.18;
        HPEN facePen = MakePen(kFgColor, face_w);
        HBRUSH eyeBrush = CreateSolidBrush(kFgColor);
        HGDIOBJ prevPen = SelectObject(hdc, facePen);
        HGDIOBJ prevBrush = SelectObject(hdc, eyeBrush);
        Ellipse(hdc,
                static_cast<int>(std::lround(eye_x - eye_r)),
                static_cast<int>(std::lround(eye_y - eye_r)),
                static_cast<int>(std::lround(eye_x + eye_r)),
                static_cast<int>(std::lround(eye_y + eye_r)));
        SelectObject(hdc, prevBrush);
        const POINT nose[3] = {
            {static_cast<LONG>(std::lround(head_cx + head_r * 0.92)),
             static_cast<LONG>(std::lround(head_cy + head_r * 0.02))},
            {static_cast<LONG>(std::lround(head_cx + head_r * 1.30)),
             static_cast<LONG>(std::lround(head_cy + head_r * 0.14))},
            {static_cast<LONG>(std::lround(head_cx + head_r * 0.88)),
             static_cast<LONG>(std::lround(head_cy + head_r * 0.30))},
        };
        Polyline(hdc, nose, 3);
        LineTo2(hdc,
                static_cast<int>(std::lround(head_cx + head_r * 0.22)),
                static_cast<int>(std::lround(head_cy + head_r * 0.55)),
                static_cast<int>(std::lround(head_cx + head_r * 0.75)),
                static_cast<int>(std::lround(head_cy + head_r * 0.48)));
        SelectObject(hdc, prevPen);
        DeleteObject(facePen);
        DeleteObject(eyeBrush);
    }

    SelectObject(hdc, oldBrush);
    SelectObject(hdc, oldPen);
    DeleteObject(fgPen);

    // Hat: brim + crown (before limbs — match hello_world.py draw order).
    // Crown uses the background brush so the top of the head circle (drawn
    // earlier) is not visible inside the hat.
    HPEN hatPen = MakePen(kHatColor, stroke);
    oldPen = SelectObject(hdc, hatPen);
    oldBrush = SelectObject(hdc, g_bgBrush);

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

    // Legs: knee flexion folds the shin backward (heel toward the body), so
    // the knee vertex points in the walking direction. The foot line is
    // ground-anchored (angle is absolute, not shin-relative).
    const double legAngles[2] = {pose.leg_l, pose.leg_r};
    const double knees[2] = {pose.knee_l, pose.knee_r};
    const double feet[2] = {pose.foot_l, pose.foot_r};
    for (int i = 0; i < 2; ++i) {
        double kx = 0, ky = 0, fx = 0, fy = 0, tx = 0, ty = 0;
        LimbEnd(cx, hip_y, legAngles[i], upper_leg, &kx, &ky);
        LimbEnd(kx, ky, legAngles[i] - knees[i], lower_leg, &fx, &fy);
        LimbEnd(fx, fy, feet[i], foot_len, &tx, &ty);
        LineTo2(hdc, static_cast<int>(std::lround(cx)), static_cast<int>(std::lround(hip_y)),
                static_cast<int>(std::lround(kx)), static_cast<int>(std::lround(ky)));
        LineTo2(hdc, static_cast<int>(std::lround(kx)), static_cast<int>(std::lround(ky)),
                static_cast<int>(std::lround(fx)), static_cast<int>(std::lround(fy)));
        LineTo2(hdc, static_cast<int>(std::lround(fx)), static_cast<int>(std::lround(fy)),
                static_cast<int>(std::lround(tx)), static_cast<int>(std::lround(ty)));
    }

    SelectObject(hdc, oldPen);
    DeleteObject(fgPen);

    // Dog trotting behind the walker, on the same ground line; drawn one
    // stroke thinner so it reads as the smaller figure.
    {
        const double kPi = 3.14159265358979323846;
        const DogPose dpose = DogTrotPose(g_phase);
        const int dog_w = (std::max)(1, stroke - 1);
        const double d_upper = 10.0 * scale;
        const double d_lower = 9.0 * scale;
        const double half_body = 14.0 * scale;
        const double dog_cx = cx - 65.0 * scale;
        const double spine_y = ground_y - 19.0 * scale + dpose.bob * scale;
        const double shoulder_x = dog_cx + half_body;
        const double hip_x = dog_cx - half_body;

        HPEN dogPen = MakePen(kFgColor, dog_w);
        oldPen = SelectObject(hdc, dogPen);
        oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH));

        // Spine
        LineTo2(hdc, static_cast<int>(std::lround(hip_x)),
                static_cast<int>(std::lround(spine_y)),
                static_cast<int>(std::lround(shoulder_x)),
                static_cast<int>(std::lround(spine_y)));

        // Legs: both legs of a diagonal pair share angle/fold; front pair
        // hangs from the shoulder, rear pair from the hip.
        const double attach[4] = {shoulder_x, shoulder_x, hip_x, hip_x};
        const double dAng[4] = {dpose.pair_a, dpose.pair_b, dpose.pair_b, dpose.pair_a};
        const double dFold[4] = {dpose.fold_a, dpose.fold_b, dpose.fold_b, dpose.fold_a};
        for (int i = 0; i < 4; ++i) {
            double kx = 0, ky = 0, px = 0, py = 0;
            LimbEnd(attach[i], spine_y, dAng[i], d_upper, &kx, &ky);
            LimbEnd(kx, ky, dAng[i] - dFold[i], d_lower, &px, &py);
            LineTo2(hdc, static_cast<int>(std::lround(attach[i])),
                    static_cast<int>(std::lround(spine_y)),
                    static_cast<int>(std::lround(kx)), static_cast<int>(std::lround(ky)));
            LineTo2(hdc, static_cast<int>(std::lround(kx)), static_cast<int>(std::lround(ky)),
                    static_cast<int>(std::lround(px)), static_cast<int>(std::lround(py)));
        }

        // Tail: up-backward from the hip, wagging about its base angle.
        double tx = 0, ty = 0;
        LimbEnd(hip_x, spine_y, kPi + 0.55 + dpose.tail, 12.0 * scale, &tx, &ty);
        LineTo2(hdc, static_cast<int>(std::lround(hip_x)),
                static_cast<int>(std::lround(spine_y)),
                static_cast<int>(std::lround(tx)), static_cast<int>(std::lround(ty)));

        // Neck (stops at the head outline), head, muzzle, ear.
        LineTo2(hdc, static_cast<int>(std::lround(shoulder_x)),
                static_cast<int>(std::lround(spine_y)),
                static_cast<int>(std::lround(shoulder_x + 4.1 * scale)),
                static_cast<int>(std::lround(spine_y - 5.9 * scale)));
        const double dh_x = shoulder_x + 7.0 * scale;
        const double dh_y = spine_y - 10.0 * scale;
        const double dh_r = 5.0 * scale;
        Ellipse(hdc,
                static_cast<int>(std::lround(dh_x - dh_r)),
                static_cast<int>(std::lround(dh_y - dh_r)),
                static_cast<int>(std::lround(dh_x + dh_r)),
                static_cast<int>(std::lround(dh_y + dh_r)));
        LineTo2(hdc, static_cast<int>(std::lround(dh_x + 3.5 * scale)),
                static_cast<int>(std::lround(dh_y + 0.8 * scale)),
                static_cast<int>(std::lround(dh_x + 10.0 * scale)),
                static_cast<int>(std::lround(dh_y + 2.2 * scale)));
        LineTo2(hdc, static_cast<int>(std::lround(dh_x - 1.5 * scale)),
                static_cast<int>(std::lround(dh_y - 4.0 * scale)),
                static_cast<int>(std::lround(dh_x - 4.0 * scale)),
                static_cast<int>(std::lround(dh_y - 9.5 * scale)));

        // Eye: filled dot.
        HBRUSH dogEyeBrush = CreateSolidBrush(kFgColor);
        HGDIOBJ prevBrush = SelectObject(hdc, dogEyeBrush);
        const double der = (std::max)(1.0, 0.9 * scale);
        Ellipse(hdc,
                static_cast<int>(std::lround(dh_x + 1.8 * scale - der)),
                static_cast<int>(std::lround(dh_y - 1.2 * scale - der)),
                static_cast<int>(std::lround(dh_x + 1.8 * scale + der)),
                static_cast<int>(std::lround(dh_y - 1.2 * scale + der)));
        SelectObject(hdc, prevBrush);
        DeleteObject(dogEyeBrush);

        SelectObject(hdc, oldBrush);
        SelectObject(hdc, oldPen);
        DeleteObject(dogPen);
    }
}

void AdvanceAnimation(HWND hwnd) {
    RECT client = {};
    GetClientRect(hwnd, &client);
    const int w = (std::max)(1L, client.right - client.left);
    const int h = (std::max)(1L, client.bottom - client.top);

    g_phase = g_phase + 0.045;
    if (g_phase >= 1.0) {
        g_phase -= 1.0;
    }
    const double speed = kWalkSpeed * (std::max)(w / 400.0, 0.75);
    g_x += speed;
    // Wrap only once the trailing dog (tail ~90 px behind at scale 1) has
    // also left the right edge; both re-enter from the left, man first.
    if (g_x > w + 40.0 + 90.0 * ViewScale(w, h)) {
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

    case WM_CLOSE:
        SaveGeometryFromHwnd(hwnd);
        DestroyWindow(hwnd);
        return 0;

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

    // CreateWindowEx width/height are outer; request client size to match Tk geometry.
    int clientW = kDefaultWidth;
    int clientH = kDefaultHeight;
    const WindowGeometry saved = LoadGeometry();
    if (saved.valid) {
        clientW = saved.w;
        clientH = saved.h;
    }

    int outerW = clientW;
    int outerH = clientH;
    if (!ClientSizeToOuter(kWindowStyle, kWindowExStyle, clientW, clientH, &outerW, &outerH)) {
        CleanupGlobals();
        return 1;
    }

    RECT work = {};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    int x = work.left + ((work.right - work.left) - outerW) / 2;
    int y = work.top + ((work.bottom - work.top) - outerH) / 2;
    if (saved.valid && GeometryOnScreen(saved.x, saved.y, outerW, outerH)) {
        x = saved.x;
        y = saved.y;
    }

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
