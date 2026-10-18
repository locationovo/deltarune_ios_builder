#include "fishhook/fishhook.c"
#include "fishhook/ProbeHook.mm"
#include "RedirectHook.mm"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#include <unistd.h>
#include <objc/runtime.h>
#include <signal.h>
#include <spawn.h>
#include <errno.h>
#include <string.h>
#include <stdatomic.h>

extern char **environ;
extern int getTargetChapter(void);
extern "C" void *SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern "C" CFTypeRef SecTaskCopyValueForEntitlement(void *task, CFStringRef entitlement, CFErrorRef *error);

static void (*libc_exit)(int);
static void (*libc__exit)(int);
static _Atomic int is_exiting = 0;
static dispatch_source_t g_pollTimer = nil;

static void writeArchLog(const char *fmt, ...) {
    @autoreleasepool {
        NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docs.count == 0) return;
        NSString *path = [docs[0] stringByAppendingPathComponent:@"arch.log"];
        FILE *f = fopen([path UTF8String], "a");
        if (!f) return;
        va_list ap; va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap); fprintf(f, "\n"); fclose(f);
    }
}

static BOOL hasEntitlementBool(void *task, CFStringRef key) {
    CFTypeRef v = SecTaskCopyValueForEntitlement(task, key, NULL);
    if (!v) return NO;
    BOOL result = NO;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) {
        result = CFBooleanGetValue((CFBooleanRef)v);
    } else {
        result = YES;
    }
    CFRelease(v);
    return result;
}

static BOOL isTrollStoreEnv(void) {
    static BOOL cached = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *task = SecTaskCreateFromSelf(kCFAllocatorDefault);
        if (task) {
            BOOL hit = NO;
            if (hasEntitlementBool(task, CFSTR("platform-application"))) hit = YES;
            if (hasEntitlementBool(task, CFSTR("com.apple.private.security.no-sandbox"))) hit = YES;
            if (hasEntitlementBool(task, CFSTR("com.apple.private.security.no-container"))) hit = YES;
            CFRelease(task);
            if (hit) { cached = YES; return; }
        }
        NSString *bundle = [[NSBundle mainBundle] bundlePath];
        NSString *parent = [bundle stringByDeletingLastPathComponent];
        NSArray *markers = @[
            @"/var/mobile/Library/Preferences/com.opa334.TrollStore.plist",
            @"/Applications/TrollStore.app",
            [parent stringByAppendingPathComponent:@".TrollStore"]
        ];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *p in markers) {
            if ([fm fileExistsAtPath:p]) { cached = YES; break; }
        }
    });
    return cached;
}

static BOOL relaunch_self(void) {
    NSString *exe = [[NSBundle mainBundle] executablePath];
    if (!exe) return NO;
    const char *exePath = [exe fileSystemRepresentation];
    pid_t pid = 0;
    char *const argv[] = { (char *)exePath, NULL };
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    sigset_t empty, def;
    sigemptyset(&empty);
    sigemptyset(&def);
    posix_spawnattr_setsigmask(&attr, &empty);
    posix_spawnattr_setsigdefault(&attr, &def);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);
    errno = 0;
    int rc = posix_spawn(&pid, exePath, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    return rc == 0;
}

static void applyChapterSwitch(void) {
    @autoreleasepool {
        NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docPaths.count == 0) return;
        NSString *docsDir = docPaths[0];
        NSFileManager *fm = [NSFileManager defaultManager];

        NSString *launcherTemp = [docsDir stringByAppendingPathComponent:@"launcher.temp"];
        if ([fm fileExistsAtPath:launcherTemp]) {
            setTargetChapter(0);
            [fm removeItemAtPath:launcherTemp error:nil];
            writeArchLog("[applyChapterSwitch] launcher.temp consumed, target=0");
            return;
        }

        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^select_chapter_(\\d+)$" options:0 error:nil];
        NSArray *docFiles = [fm contentsOfDirectoryAtPath:docsDir error:nil];
        if (docFiles == nil) return;

        for (NSString *fileName in docFiles) {
            NSTextCheckingResult *match = [regex firstMatchInString:fileName options:0 range:NSMakeRange(0, fileName.length)];
            if (match) {
                NSRange numRange = [match rangeAtIndex:1];
                int n = [[fileName substringWithRange:numRange] intValue];
                if (n >= 0 && n <= 9) {
                    setTargetChapter(n);
                    writeArchLog("[applyChapterSwitch] found %s chapter %d", [fileName UTF8String], n);
                    [fm removeItemAtPath:[docsDir stringByAppendingPathComponent:fileName] error:nil];
                    return;
                }
            }
        }
        writeArchLog("[applyChapterSwitch] no trigger, target=0");
    }
}

static void sendOpenURL(void) {
    NSURL *url = [NSURL URLWithString:@"dios://"];
    if ([NSThread isMainThread]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        });
    }
}

static void do_restart(void) {
    if (isTrollStoreEnv()) {
        if (relaunch_self()) _exit(0);
    }
    sendOpenURL();
    usleep(300000);
}

static void handleExitBefore(void) {
    if (atomic_exchange(&is_exiting, 1)) return;
    @autoreleasepool {
        NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docsDir = docPaths.count ? docPaths[0] : nil;
        if (!docsDir) return;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *docFiles = [fm contentsOfDirectoryAtPath:docsDir error:nil];
        BOOL pending = NO;
        for (NSString *name in docFiles) {
            if ([name hasPrefix:@"select_chapter_"]) { pending = YES; break; }
        }
        if (!pending && [fm fileExistsAtPath:[docsDir stringByAppendingPathComponent:@"launcher.temp"]]) {
            pending = YES;
        }
        if (pending) do_restart();
    }
}

static void my_exit(int code) { handleExitBefore(); libc_exit(code); }
static void my__exit(int code) { handleExitBefore(); libc__exit(code); }

static void startPoller(void) {
    if (g_pollTimer) return;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    g_pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(g_pollTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 16 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(g_pollTimer, ^{
        @autoreleasepool {
            if (atomic_load(&is_exiting)) return;
            NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            if (docs.count == 0) return;
            NSString *docDir = docs[0];
            NSFileManager *fm = [NSFileManager defaultManager];
            BOOL pending = NO;
            for (int i = 1; i <= 9; i++) {
                if ([fm fileExistsAtPath:[docDir stringByAppendingPathComponent:[NSString stringWithFormat:@"select_chapter_%d", i]]]) { pending = YES; break; }
            }
            if (!pending && [fm fileExistsAtPath:[docDir stringByAppendingPathComponent:@"launcher.temp"]]) {
                pending = YES;
            }
            if (pending) {
                if (atomic_exchange(&is_exiting, 1)) return;
                do_restart();
            }
        }
    });
    dispatch_resume(g_pollTimer);
}

__attribute__((constructor(100))) static void chapterInit(void) {
    applyChapterSwitch();
    struct rebinding rb[] = {
        {"exit",  (void*)my_exit,  (void**)&libc_exit},
        {"_exit", (void*)my__exit, (void**)&libc__exit},
    };
    rebind_symbols(rb, 2);
    startPoller();
}

__attribute__((constructor(101))) static void probeInitConstructor(void) { installProbeHooks(); }

static BOOL dios_openURL(id self, SEL _cmd, UIApplication *app, NSURL *url, NSDictionary *opts) {
    return YES;
}

__attribute__((constructor(104))) static void installURLHandler(void) {
    Class cls = NSClassFromString(@"iPad_RunnerAppDelegate");
    if (!cls) return;
    SEL sel = @selector(application:openURL:options:);
    if (!class_getInstanceMethod(cls, sel)) {
        class_addMethod(cls, sel, (IMP)dios_openURL, "B@:@@@");
    }
}

void minimalfunction() {}
