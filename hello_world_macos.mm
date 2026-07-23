// macOS Cocoa clone of hello_world.py / hello_world.cpp — stick figure with a
// hat walking across a dark window (title/colors/minsize/icon matched).

#import <Cocoa/Cocoa.h>

#include <algorithm>
#include <cmath>
#include <string>

namespace {

constexpr int kDefaultWidth = 400;
constexpr int kDefaultHeight = 200;
constexpr int kMinWidth = 300;
constexpr int kMinHeight = 150;

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

    const double scale = std::max(0.55, std::min(w / 400.0, h / 200.0));
    const Pose pose = WalkPose(phase);
    const double cx = xPos;
    const double cy = h * 0.55 + pose.bob * scale;

    const double head_r = 12.0 * scale;
    const double torso = 34.0 * scale;
    const double upper_leg = 22.0 * scale;
    const double lower_leg = 20.0 * scale;
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

    // Ground line
    const double ground_y = hip_y + upper_leg + lower_leg + 4.0 * scale;
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
        CGContextStrokeRect(ctx, CGRectMake(left, FlipY(botY, h),
                                            static_cast<CGFloat>(crown_w * 2.0), height));
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

    // Legs
    const double legAngles[2] = {pose.leg_l, pose.leg_r};
    const double knees[2] = {pose.knee_l, pose.knee_r};
    for (int i = 0; i < 2; ++i) {
        double kx = 0, ky = 0, fx = 0, fy = 0;
        LimbEnd(cx, hip_y, legAngles[i], upper_leg, &kx, &ky);
        LimbEnd(kx, ky, legAngles[i] + knees[i], lower_leg, &fx, &fy);
        StrokeLine(ctx, static_cast<CGFloat>(cx), FlipY(hip_y, h), static_cast<CGFloat>(kx),
                   FlipY(ky, h));
        StrokeLine(ctx, static_cast<CGFloat>(kx), FlipY(ky, h), static_cast<CGFloat>(fx),
                   FlipY(fy, h));
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
    self.phase = self.phase + 0.045;
    if (self.phase >= 1.0) {
        self.phase -= 1.0;
    }
    const double speed = kWalkSpeed * std::max(static_cast<double>(w) / 400.0, 0.75);
    self.xPos += speed;
    if (self.xPos > static_cast<double>(w) + 40.0) {
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

    // contentRect is the client area — match Tk geometry 400x200.
    const NSRect contentRect = NSMakeRect(0, 0, kDefaultWidth, kDefaultHeight);
    self.window = [[NSWindow alloc] initWithContentRect:contentRect
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Hello World";
    self.window.backgroundColor =
        [NSColor colorWithCalibratedRed:kBgR green:kBgG blue:kBgB alpha:1.0];
    [self.window setContentMinSize:NSMakeSize(kMinWidth, kMinHeight)];
    [self.window center];
    self.window.releasedWhenClosed = NO;

    self.walker = [[WalkerView alloc] initWithFrame:contentRect];
    self.walker.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.walker;

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
