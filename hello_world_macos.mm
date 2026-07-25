// macOS Cocoa clone of hello_world.py / hello_world.cpp — stick figure with a
// hat walking across a dark window (title/colors/minsize/icon matched).

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>

namespace {

constexpr int kDefaultWidth = 400;
constexpr int kDefaultHeight = 200;
constexpr int kMinWidth = 300;
constexpr int kMinHeight = 150;

// Content size + outer frame origin (same JSON keys as the Python / Win32 apps).
struct WindowGeometry {
    int x = 0;
    int y = 0;
    int w = kDefaultWidth;
    int h = kDefaultHeight;
    bool valid = false;
};

// Match hello_world.py: bg #1a1a2e, fg #eaeaea, hat #c9a227, ground #2a2a44
constexpr CGFloat kBgR = 0x1a / 255.0, kBgG = 0x1a / 255.0, kBgB = 0x2e / 255.0;
constexpr CGFloat kFgR = 0xea / 255.0, kFgG = 0xea / 255.0, kFgB = 0xea / 255.0;
constexpr CGFloat kHatR = 0xc9 / 255.0, kHatG = 0xa2 / 255.0, kHatB = 0x27 / 255.0;
constexpr CGFloat kGroundR = 0x2a / 255.0, kGroundG = 0x2a / 255.0, kGroundB = 0x44 / 255.0;

constexpr NSTimeInterval kFrameSeconds = 0.050;
constexpr double kWalkSpeed = 2.4;
constexpr double kTau = 6.28318530717958647692;

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
    return std::max(0.55, std::min(w / 400.0, h / 200.0));
}

void LimbEnd(double x, double y, double angle, double length, double* ox, double* oy) {
    // angle 0 = straight down; positive = clockwise (screen y grows downward).
    *ox = x + length * std::sin(angle);
    *oy = y + length * std::cos(angle);
}

// Convert top-left y (Win32/Tk style) to AppKit bottom-left y for a view of height h.
inline CGFloat FlipY(double yTop, CGFloat h) {
    return static_cast<CGFloat>(h - yTop);
}

std::string ExeDirectory() {
    @autoreleasepool {
        NSString* exe = [[NSProcessInfo processInfo] arguments].firstObject;
        if (!exe) {
            return ".";
        }
        NSString* dir = [exe stringByDeletingLastPathComponent];
        if (dir.length == 0) {
            return ".";
        }
        return std::string([dir fileSystemRepresentation]);
    }
}

// ~/Library/Application Support/CodingAgent/hello_world_cpp_geometry.json
// (C++ only; Python uses hello_world_geometry.json in the same folder.)
std::string GeometryConfigPath() {
    @autoreleasepool {
        NSArray<NSString*>* urls = NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString* base = urls.firstObject;
        if (!base) {
            base = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
        }
        NSString* dir = [base stringByAppendingPathComponent:@"CodingAgent"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSString* path = [dir stringByAppendingPathComponent:@"hello_world_cpp_geometry.json"];
        return std::string([path fileSystemRepresentation]);
    }
}

WindowGeometry LoadGeometry() {
    WindowGeometry g{};
    const std::string path = GeometryConfigPath();
    FILE* fp = std::fopen(path.c_str(), "rb");
    if (!fp) {
        return g;
    }
    char buf[512] = {};
    const size_t n = std::fread(buf, 1, sizeof(buf) - 1, fp);
    std::fclose(fp);
    if (n == 0) {
        return g;
    }
    buf[n] = '\0';

    int x = 0, y = 0, w = 0, h = 0;
    const char* px = std::strstr(buf, "\"x\"");
    const char* py = std::strstr(buf, "\"y\"");
    const char* pw = std::strstr(buf, "\"w\"");
    const char* ph = std::strstr(buf, "\"h\"");
    if (!px || !py || !pw || !ph) {
        return g;
    }
    if (std::sscanf(px, "\"x\"%*[^0-9-]%d", &x) != 1) {
        return g;
    }
    if (std::sscanf(py, "\"y\"%*[^0-9-]%d", &y) != 1) {
        return g;
    }
    if (std::sscanf(pw, "\"w\"%*[^0-9-]%d", &w) != 1) {
        return g;
    }
    if (std::sscanf(ph, "\"h\"%*[^0-9-]%d", &h) != 1) {
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
    const std::string path = GeometryConfigPath();
    FILE* fp = std::fopen(path.c_str(), "wb");
    if (!fp) {
        return;
    }
    std::fprintf(fp,
                 "{\n  \"x\": %d,\n  \"y\": %d,\n  \"w\": %d,\n  \"h\": %d\n}\n",
                 g.x, g.y, g.w, g.h);
    std::fclose(fp);
}

void SaveGeometryFromWindow(NSWindow* window) {
    if (!window) {
        return;
    }
    const NSRect frame = window.frame;
    const NSRect content = [window contentRectForFrameRect:frame];
    WindowGeometry g{};
    // Store top-left style origin for cross-app JSON consistency: convert from
    // AppKit bottom-left frame origin to a top-left-ish x/y matching Tk/Win32.
    NSScreen* screen = window.screen ?: [NSScreen mainScreen];
    const CGFloat screenH = screen ? screen.frame.size.height : 0;
    g.x = static_cast<int>(std::lround(frame.origin.x));
    g.y = static_cast<int>(std::lround(screenH - frame.origin.y - frame.size.height));
    g.w = static_cast<int>(std::lround(content.size.width));
    g.h = static_cast<int>(std::lround(content.size.height));
    if (g.w < kMinWidth) {
        g.w = kMinWidth;
    }
    if (g.h < kMinHeight) {
        g.h = kMinHeight;
    }
    g.valid = true;
    SaveGeometry(g);
}

void StrokeLine(CGContextRef ctx, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, x1, y1);
    CGContextAddLineToPoint(ctx, x2, y2);
    CGContextStrokePath(ctx);
}

void DrawWalker(CGContextRef ctx, CGFloat w, CGFloat h, double phase, double xPos) {
    if (w <= 0 || h <= 0) {
        return;
    }

    CGContextSetRGBFillColor(ctx, kBgR, kBgG, kBgB, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, w, h));

    const double scale = ViewScale(w, h);
    const Pose pose = WalkPose(phase);
    const double cx = xPos;
    const double base_cy = h * 0.55;  // un-bobbed body reference; anchors the ground
    const double cy = base_cy + pose.bob * scale;

    const double head_r = 12.0 * scale;
    const double torso = 34.0 * scale;
    const double upper_leg = 22.0 * scale;
    const double lower_leg = 20.0 * scale;
    const double foot_len = 8.0 * scale;
    const double upper_arm = 16.0 * scale;
    const double lower_arm = 14.0 * scale;
    const CGFloat stroke =
        static_cast<CGFloat>(std::max(2, static_cast<int>(std::lround(3.0 * scale))));

    const double hip_y = cy + torso;
    const double shoulder_y = cy + 8.0 * scale;
    const double head_cx = cx;
    const double head_cy = cy - head_r - 2.0 * scale;

    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);

    // Ground line: anchored to the un-bobbed pose (does not bounce with the
    // body) at exactly straight-leg reach, so planted feet touch it.
    const double ground_y = base_cy + torso + upper_leg + lower_leg;
    CGContextSetRGBStrokeColor(ctx, kGroundR, kGroundG, kGroundB, 1.0);
    CGContextSetLineWidth(ctx, static_cast<CGFloat>(std::max(1, static_cast<int>(stroke) - 1)));
    StrokeLine(ctx, 0, FlipY(ground_y, h), w, FlipY(ground_y, h));

    CGContextSetRGBStrokeColor(ctx, kFgR, kFgG, kFgB, 1.0);
    CGContextSetLineWidth(ctx, stroke);

    // Torso
    StrokeLine(ctx, static_cast<CGFloat>(cx), FlipY(cy, h), static_cast<CGFloat>(cx),
               FlipY(hip_y, h));

    // Head (oval outline)
    {
        const CGFloat hx = static_cast<CGFloat>(head_cx - head_r);
        const CGFloat hy = FlipY(head_cy + head_r, h);
        const CGFloat hd = static_cast<CGFloat>(head_r * 2.0);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(hx, hy, hd, hd));
    }

    // Face (right profile, facing the walking direction): eye dot, nose
    // wedge poking past the head outline, short mouth line.
    {
        const CGFloat face_w =
            static_cast<CGFloat>(std::max(1, static_cast<int>(stroke) - 1));
        const double eye_r = std::max(1.2, head_r * 0.12);
        const double eye_x = head_cx + head_r * 0.38;
        const double eye_y = head_cy - head_r * 0.18;
        CGContextSetRGBFillColor(ctx, kFgR, kFgG, kFgB, 1.0);
        CGContextFillEllipseInRect(
            ctx, CGRectMake(static_cast<CGFloat>(eye_x - eye_r), FlipY(eye_y + eye_r, h),
                            static_cast<CGFloat>(eye_r * 2.0),
                            static_cast<CGFloat>(eye_r * 2.0)));
        CGContextSetLineWidth(ctx, face_w);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, static_cast<CGFloat>(head_cx + head_r * 0.92),
                             FlipY(head_cy + head_r * 0.02, h));
        CGContextAddLineToPoint(ctx, static_cast<CGFloat>(head_cx + head_r * 1.30),
                                FlipY(head_cy + head_r * 0.14, h));
        CGContextAddLineToPoint(ctx, static_cast<CGFloat>(head_cx + head_r * 0.88),
                                FlipY(head_cy + head_r * 0.30, h));
        CGContextStrokePath(ctx);
        StrokeLine(ctx, static_cast<CGFloat>(head_cx + head_r * 0.22),
                   FlipY(head_cy + head_r * 0.55, h),
                   static_cast<CGFloat>(head_cx + head_r * 0.75),
                   FlipY(head_cy + head_r * 0.48, h));
    }

    // Hat: brim + crown (before limbs — match hello_world.py draw order)
    CGContextSetRGBStrokeColor(ctx, kHatR, kHatG, kHatB, 1.0);
    CGContextSetLineWidth(ctx, stroke);

    const double brim_w = head_r * 1.7;
    const double brim_y = head_cy - head_r * 0.55;
    StrokeLine(ctx, static_cast<CGFloat>(head_cx - brim_w), FlipY(brim_y, h),
               static_cast<CGFloat>(head_cx + brim_w), FlipY(brim_y, h));

    const double crown_w = head_r * 1.05;
    const double crown_h = head_r * 1.15;
    {
        const CGFloat left = static_cast<CGFloat>(head_cx - crown_w);
        const CGFloat topY = brim_y - crown_h;
        const CGFloat botY = brim_y;
        const CGFloat height = static_cast<CGFloat>(botY - topY);
        const CGRect crownRect = CGRectMake(left, FlipY(botY, h),
                                            static_cast<CGFloat>(crown_w * 2.0), height);
        // Crown interior is filled with the background color so the top of
        // the head circle (drawn earlier) is not visible inside the hat.
        CGContextSetRGBFillColor(ctx, kBgR, kBgG, kBgB, 1.0);
        CGContextFillRect(ctx, crownRect);
        CGContextStrokeRect(ctx, crownRect);
    }

    CGContextSetRGBStrokeColor(ctx, kFgR, kFgG, kFgB, 1.0);
    CGContextSetLineWidth(ctx, stroke);

    // Arms
    const double armAngles[2] = {pose.arm_l, pose.arm_r};
    for (double ang : armAngles) {
        double ex = 0, ey = 0, hx = 0, hy = 0;
        LimbEnd(cx, shoulder_y, ang, upper_arm, &ex, &ey);
        LimbEnd(ex, ey, ang + 0.25, lower_arm, &hx, &hy);
        StrokeLine(ctx, static_cast<CGFloat>(cx), FlipY(shoulder_y, h),
                   static_cast<CGFloat>(ex), FlipY(ey, h));
        StrokeLine(ctx, static_cast<CGFloat>(ex), FlipY(ey, h), static_cast<CGFloat>(hx),
                   FlipY(hy, h));
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
        StrokeLine(ctx, static_cast<CGFloat>(cx), FlipY(hip_y, h), static_cast<CGFloat>(kx),
                   FlipY(ky, h));
        StrokeLine(ctx, static_cast<CGFloat>(kx), FlipY(ky, h), static_cast<CGFloat>(fx),
                   FlipY(fy, h));
        StrokeLine(ctx, static_cast<CGFloat>(fx), FlipY(fy, h), static_cast<CGFloat>(tx),
                   FlipY(ty, h));
    }

    // Dog trotting behind the walker, on the same ground line; drawn one
    // stroke thinner so it reads as the smaller figure.
    {
        const double kPi = 3.14159265358979323846;
        const DogPose dpose = DogTrotPose(phase);
        const CGFloat dog_w =
            static_cast<CGFloat>(std::max(1, static_cast<int>(stroke) - 1));
        const double d_upper = 10.0 * scale;
        const double d_lower = 9.0 * scale;
        const double half_body = 14.0 * scale;
        const double dog_cx = cx - 65.0 * scale;
        const double spine_y = ground_y - 19.0 * scale + dpose.bob * scale;
        const double shoulder_x = dog_cx + half_body;
        const double hip_x = dog_cx - half_body;

        CGContextSetLineWidth(ctx, dog_w);

        // Spine
        StrokeLine(ctx, static_cast<CGFloat>(hip_x), FlipY(spine_y, h),
                   static_cast<CGFloat>(shoulder_x), FlipY(spine_y, h));

        // Legs: both legs of a diagonal pair share angle/fold; front pair
        // hangs from the shoulder, rear pair from the hip.
        const double attach[4] = {shoulder_x, shoulder_x, hip_x, hip_x};
        const double dAng[4] = {dpose.pair_a, dpose.pair_b, dpose.pair_b, dpose.pair_a};
        const double dFold[4] = {dpose.fold_a, dpose.fold_b, dpose.fold_b, dpose.fold_a};
        for (int i = 0; i < 4; ++i) {
            double kx = 0, ky = 0, px = 0, py = 0;
            LimbEnd(attach[i], spine_y, dAng[i], d_upper, &kx, &ky);
            LimbEnd(kx, ky, dAng[i] - dFold[i], d_lower, &px, &py);
            StrokeLine(ctx, static_cast<CGFloat>(attach[i]), FlipY(spine_y, h),
                       static_cast<CGFloat>(kx), FlipY(ky, h));
            StrokeLine(ctx, static_cast<CGFloat>(kx), FlipY(ky, h),
                       static_cast<CGFloat>(px), FlipY(py, h));
        }

        // Tail: up-backward from the hip, wagging about its base angle.
        double tx = 0, ty = 0;
        LimbEnd(hip_x, spine_y, kPi + 0.55 + dpose.tail, 12.0 * scale, &tx, &ty);
        StrokeLine(ctx, static_cast<CGFloat>(hip_x), FlipY(spine_y, h),
                   static_cast<CGFloat>(tx), FlipY(ty, h));

        // Neck (stops at the head outline), head, muzzle, ear, eye.
        StrokeLine(ctx, static_cast<CGFloat>(shoulder_x), FlipY(spine_y, h),
                   static_cast<CGFloat>(shoulder_x + 4.1 * scale),
                   FlipY(spine_y - 5.9 * scale, h));
        const double dh_x = shoulder_x + 7.0 * scale;
        const double dh_y = spine_y - 10.0 * scale;
        const double dh_r = 5.0 * scale;
        CGContextStrokeEllipseInRect(
            ctx, CGRectMake(static_cast<CGFloat>(dh_x - dh_r), FlipY(dh_y + dh_r, h),
                            static_cast<CGFloat>(dh_r * 2.0),
                            static_cast<CGFloat>(dh_r * 2.0)));
        StrokeLine(ctx, static_cast<CGFloat>(dh_x + 3.5 * scale),
                   FlipY(dh_y + 0.8 * scale, h),
                   static_cast<CGFloat>(dh_x + 10.0 * scale),
                   FlipY(dh_y + 2.2 * scale, h));
        StrokeLine(ctx, static_cast<CGFloat>(dh_x - 1.5 * scale),
                   FlipY(dh_y - 4.0 * scale, h),
                   static_cast<CGFloat>(dh_x - 4.0 * scale),
                   FlipY(dh_y - 9.5 * scale, h));
        const double der = std::max(1.0, 0.9 * scale);
        CGContextSetRGBFillColor(ctx, kFgR, kFgG, kFgB, 1.0);
        CGContextFillEllipseInRect(
            ctx, CGRectMake(static_cast<CGFloat>(dh_x + 1.8 * scale - der),
                            FlipY(dh_y - 1.2 * scale + der, h),
                            static_cast<CGFloat>(der * 2.0),
                            static_cast<CGFloat>(der * 2.0)));
    }
}

}  // namespace

@interface WalkerView : NSView
@property(nonatomic, assign) double phase;
@property(nonatomic, assign) double xPos;
@property(nonatomic, strong) NSTimer* timer;
- (void)startAnimation;
- (void)stopAnimation;
@end

@implementation WalkerView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _phase = 0.0;
        _xPos = 40.0;
        self.wantsLayer = YES;  // layer-backed; drawRect content is buffered
    }
    return self;
}

- (BOOL)isFlipped {
    // Keep AppKit default (bottom-left origin); DrawWalker flips y itself to match Tk/Win32.
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    if (!ctx) {
        return;
    }
    const NSRect bounds = self.bounds;
    DrawWalker(ctx, bounds.size.width, bounds.size.height, self.phase, self.xPos);
}

- (void)startAnimation {
    [self stopAnimation];
    __weak WalkerView* weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:kFrameSeconds
                                        repeats:YES
                                          block:^(__unused NSTimer* t) {
                                            WalkerView* view = weakSelf;
                                            if (!view) {
                                                return;
                                            }
                                            [view advance];
                                          }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stopAnimation {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)advance {
    const CGFloat w = std::max<CGFloat>(1.0, self.bounds.size.width);
    const CGFloat h = std::max<CGFloat>(1.0, self.bounds.size.height);
    self.phase = self.phase + 0.045;
    if (self.phase >= 1.0) {
        self.phase -= 1.0;
    }
    const double speed = kWalkSpeed * std::max(static_cast<double>(w) / 400.0, 0.75);
    self.xPos += speed;
    // Wrap only once the trailing dog (tail ~90 px behind at scale 1) has
    // also left the right edge; both re-enter from the left, man first.
    if (self.xPos > static_cast<double>(w) + 40.0 +
                        90.0 * ViewScale(static_cast<double>(w), static_cast<double>(h))) {
        self.xPos = -40.0;
    }
    [self setNeedsDisplay:YES];
}

- (void)dealloc {
    [self stopAnimation];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) WalkerView* walker;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;

    const NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

    const WindowGeometry saved = LoadGeometry();
    const CGFloat contentW = saved.valid ? static_cast<CGFloat>(saved.w) : kDefaultWidth;
    const CGFloat contentH = saved.valid ? static_cast<CGFloat>(saved.h) : kDefaultHeight;

    // contentRect is the client area — match Tk geometry 400x200 (or restored size).
    const NSRect contentRect = NSMakeRect(0, 0, contentW, contentH);
    self.window = [[NSWindow alloc] initWithContentRect:contentRect
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Hello World";
    self.window.backgroundColor =
        [NSColor colorWithCalibratedRed:kBgR green:kBgG blue:kBgB alpha:1.0];
    [self.window setContentMinSize:NSMakeSize(kMinWidth, kMinHeight)];
    self.window.releasedWhenClosed = NO;

    if (saved.valid) {
        // JSON stores top-left style y (Tk/Win32); convert to AppKit bottom-left frame.
        NSScreen* screen = [NSScreen mainScreen];
        const CGFloat screenH = screen ? screen.frame.size.height : 0;
        const NSRect curFrame = self.window.frame;
        const CGFloat frameH = curFrame.size.height;
        const CGFloat frameW = curFrame.size.width;
        const CGFloat frameX = static_cast<CGFloat>(saved.x);
        const CGFloat frameY = screenH - static_cast<CGFloat>(saved.y) - frameH;
        NSRect placed = NSMakeRect(frameX, frameY, frameW, frameH);
        // If the restored top-left is off every screen, center instead.
        BOOL onScreen = NO;
        for (NSScreen* s in [NSScreen screens]) {
            if (NSPointInRect(NSMakePoint(frameX + 20, frameY + frameH - 20), s.frame)) {
                onScreen = YES;
                break;
            }
        }
        if (onScreen) {
            [self.window setFrame:placed display:NO];
        } else {
            [self.window center];
        }
    } else {
        [self.window center];
    }

    NSTabView* tabView = [[NSTabView alloc] initWithFrame:contentRect];
    tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSTabViewItem* itemOne = [[NSTabViewItem alloc] initWithIdentifier:@"one"];
    itemOne.label = @"one";
    self.walker = [[WalkerView alloc] initWithFrame:contentRect];
    self.walker.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    itemOne.view = self.walker;
    [tabView addTabViewItem:itemOne];

    NSTabViewItem* itemTwo = [[NSTabViewItem alloc] initWithIdentifier:@"two"];
    itemTwo.label = @"two";
    NSView* placeholder = [[NSView alloc] initWithFrame:contentRect];
    placeholder.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    placeholder.wantsLayer = YES;
    placeholder.layer.backgroundColor =
        [[NSColor colorWithCalibratedRed:kBgR green:kBgG blue:kBgB alpha:1.0] CGColor];

    NSTextField* label = [[NSTextField alloc] initWithFrame:placeholder.bounds];
    label.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    label.stringValue = @"TAB TWO PLACEHOLDER";
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.textColor = [NSColor colorWithCalibratedRed:kFgR green:kFgG blue:kFgB alpha:1.0];
    label.alignment = NSTextAlignmentCenter;
    [label setFont:[NSFont systemFontOfSize:24]];
    [placeholder addSubview:label];
    itemTwo.view = placeholder;
    [tabView addTabViewItem:itemTwo];

    [tabView selectTabViewItem:itemOne];
    self.window.contentView = tabView;

    [self tryLoadIcon];

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.walker startAnimation];
}

- (void)tryLoadIcon {
    // Prefer hello_world.icns next to the executable, then cwd (repo root when launched
    // via Desktop shortcut), then .ico is not used on macOS.
    NSMutableArray<NSString*>* candidates = [NSMutableArray array];
    const std::string exeDir = ExeDirectory();
    [candidates addObject:[NSString stringWithUTF8String:(exeDir + "/hello_world.icns").c_str()]];
    [candidates addObject:[[[NSFileManager defaultManager] currentDirectoryPath]
                             stringByAppendingPathComponent:@"hello_world.icns"]];

    // Also look beside the source-tree binary when running from repo root.
    NSString* argv0 = [[NSProcessInfo processInfo] arguments].firstObject;
    if (argv0) {
        NSString* abs = argv0;
        if (![abs isAbsolutePath]) {
            abs = [[[NSFileManager defaultManager] currentDirectoryPath]
                stringByAppendingPathComponent:argv0];
        }
        NSString* dir = [abs stringByDeletingLastPathComponent];
        [candidates addObject:[dir stringByAppendingPathComponent:@"hello_world.icns"]];
    }

    for (NSString* path in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSImage* image = [[NSImage alloc] initWithContentsOfFile:path];
            if (image) {
                NSApp.applicationIconImage = image;
                return;
            }
        }
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;
    SaveGeometryFromWindow(self.window);
    [self.walker stopAnimation];
}

@end

int main(int argc, const char* argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        // Same idea as Windows SUBSYSTEM:WINDOWS / pythonw — foreground app, no console UI.
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        AppDelegate* delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        // No MainMenu.nib / NSApplicationMain: finish launching (fires the delegate
        // callback), then enter the event loop.
        [app finishLaunching];
        [app run];
    }
    return 0;
}
