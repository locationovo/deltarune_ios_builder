//
//  arch.mm
//  Deltarune
//
//  Chapter switching support.
//  On app launch, scans Documents for select_chapter_N.
//  Instead of copying data files, sets a global target chapter.
//  RedirectHook (fopen) rewrites game.ios -> gamN.droid at load time.
//

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
#include <sys/time.h>

extern char **environ;
extern int getTargetChapter(void);
extern "C" void *SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern "C" CFTypeRef SecTaskCopyValueForEntitlement(void *task, CFStringRef entitlement, CFErrorRef *error);

static void (*libc_exit)(int);
static void (*libc__exit)(int);
static _Atomic int is_exiting = 0;
static dispatch_source_t poller_timer = nil;

static void write_log(const char *fmt, ...) {
    @autoreleasepool {
        NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docs.count == 0) return;
        NSString *path = [docs[0] stringByAppendingPathComponent:@"arch.log"];
        FILE *f = fopen([path UTF8String], "a");
        if (!f) return;
        struct timeval tv;
        gettimeofday(&tv, NULL);
        struct tm tm_buf;
        localtime_r(&tv.tv_sec, &tm_buf);
        va_list ap; va_start(ap, fmt);
        char buf[2048];
        vsnprintf(buf, sizeof(buf), fmt, ap);
        va_end(ap);
        fprintf(f, "[%04d-%02d-%02d %02d:%02d:%02d.%03d] %s\n",
                tm_buf.tm_year + 1900, tm_buf.tm_mon + 1, tm_buf.tm_mday,
                tm_buf.tm_hour, tm_buf.tm_min, tm_buf.tm_sec,
                (int)(tv.tv_usec / 1000), buf);
        fclose(f);
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
        int plat = -1, nosb = -1, nocon = -1;
        void *task = SecTaskCreateFromSelf(kCFAllocatorDefault);
        if (task) {
            plat = (int)hasEntitlementBool(task, CFSTR("platform-application"));
            nosb = (int)hasEntitlementBool(task, CFSTR("com.apple.private.security.no-sandbox"));
            nocon = (int)hasEntitlementBool(task, CFSTR("com.apple.private.security.no-container"));
            CFRelease(task);
        }
        BOOL hit = (plat == 1 || nosb == 1 || nocon == 1);
        if (!hit) {
            NSString *bundle = [[NSBundle mainBundle] bundlePath];
            NSString *parent = [bundle stringByDeletingLastPathComponent];
            NSString *grand = [parent stringByDeletingLastPathComponent];
            NSArray *markers = @[
                @"/var/mobile/Library/Preferences/com.opa334.TrollStore.plist",
                @"/var/mobile/Library/Preferences/com.opa334.trollstorepreferences.plist",
                @"/Applications/TrollStore.app",
                [parent stringByAppendingPathComponent:@".TrollStore"],
                [grand stringByAppendingPathComponent:@".TrollStore"],
            ];
            NSFileManager *fm = [NSFileManager defaultManager];
            for (NSString *p in markers) {
                if ([fm fileExistsAtPath:p]) { hit = YES; break; }
            }
        }
        cached = hit;
        write_log("[env] TrollStore=%d platform=%d nosandbox=%d nocontainer=%d",
                  (int)hit, plat, nosb, nocon);
    });
    return cached;
}

static BOOL relaunch_self(void) {
    NSString *exe = [[NSBundle mainBundle] executablePath];
    if (!exe) { write_log("[relaunch] no executablePath"); return NO; }
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
    int e = errno;
    posix_spawnattr_destroy(&attr);

    write_log("[relaunch] posix_spawn rc=%d pid=%d errno=%d(%s)",
              rc, (int)pid, e, strerror(e));
    return rc == 0;
}

static void handle_pending_switch(void) {
    @autoreleasepool {
        NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docPaths.count == 0) return;
        NSString *docsDir = docPaths[0];
        NSFileManager *fm = [NSFileManager defaultManager];

        NSString *quitTemp = [docsDir stringByAppendingPathComponent:@"quit.temp"];
        if ([fm fileExistsAtPath:quitTemp]) {
            [fm removeItemAtPath:quitTemp error:nil];
            write_log("[cleanup] removed stale quit.temp");
        }

        NSString *launcherTemp = [docsDir stringByAppendingPathComponent:@"launcher.temp"];
        if ([fm fileExistsAtPath:launcherTemp]) {
            setTargetChapter(0);
            [fm removeItemAtPath:launcherTemp error:nil];
            write_log("[applyChapterSwitch] launcher");
            return;
        }

        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^select_chapter_(\\d+)$" options:0 error:nil];
        NSArray *docFiles = [fm contentsOfDirectoryAtPath:docsDir error:nil];
        if (docFiles == nil) return;

        for (NSString *fileName in docFiles) {
            NSTextCheckingResult *match = [regex firstMatchInString:fileName options:0 range:NSMakeRange(0, fileName.length)];
            if (match) {
                NSRange numRange = [match rangeAtIndex:1];
                NSString *numStr = [fileName substringWithRange:numRange];
                int n = [numStr intValue];
                if (n >= 0 && n <= 9) {
                    setTargetChapter(n);
                    write_log("[applyChapterSwitch] found %s chapter %d", [fileName UTF8String], n);
                    write_log("[applyChapterSwitch] setTargetChapter(%d)", n);
                    [fm removeItemAtPath:[docsDir stringByAppendingPathComponent:fileName] error:nil];
                    return;
                }
            }
        }
    }
}

static void do_relaunch_or_fallback(const char *tag) {
    if (isTrollStoreEnv()) {
        write_log("[%s] TrollStore relaunch", tag);
        if (relaunch_self()) _exit(0);
        write_log("[%s] relaunch failed, fallback", tag);
    } else {
        write_log("[%s] signed env, openURL fallback", tag);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"dios://"] options:@{} completionHandler:^(BOOL success) {
            write_log("[%s] openURL callback: %d", tag, success);
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            kill(getpid(), SIGKILL);
        });
    });
}

static void check_pending_before_exit(void) {
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
        if (!pending && [fm fileExistsAtPath:[docsDir stringByAppendingPathComponent:@"launcher.temp"]]) pending = YES;
        if (!pending && [fm fileExistsAtPath:[docsDir stringByAppendingPathComponent:@"quit.temp"]]) pending = YES;

        if (!pending) {
            write_log("[handleExitBefore] pending=0");
            return;
        }

        write_log("[handleExitBefore] pending=1");
        do_relaunch_or_fallback("exit");
    }
}

static void hook_exit(int code) { check_pending_before_exit(); libc_exit(code); }
static void hook__exit(int code) { check_pending_before_exit(); libc__exit(code); }

static void start_temp_poller(void) {
    if (poller_timer) return;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    poller_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(poller_timer, dispatch_time(DISPATCH_TIME_NOW, 0), 16 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);

    dispatch_source_set_event_handler(poller_timer, ^{
        @autoreleasepool {
            if (atomic_load(&is_exiting)) return;

            NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            if (docs.count == 0) return;
            NSString *docDir = docs[0];
            NSFileManager *fm = [NSFileManager defaultManager];

            BOOL hasPending = NO;
            if ([fm fileExistsAtPath:[docDir stringByAppendingPathComponent:@"launcher.temp"]]) hasPending = YES;
            if ([fm fileExistsAtPath:[docDir stringByAppendingPathComponent:@"quit.temp"]]) hasPending = YES;
            for (int i = 1; i <= 9; i++) {
                NSString *t = [docDir stringByAppendingPathComponent:[NSString stringWithFormat:@"select_chapter_%d", i]];
                if ([fm fileExistsAtPath:t]) { hasPending = YES; break; }
            }
            if (!hasPending) return;

            if (atomic_exchange(&is_exiting, 1)) return;
            write_log("[poller] immediate relaunch");
            do_relaunch_or_fallback("poller");
        }
    });
    dispatch_resume(poller_timer);
}

__attribute__((constructor(100))) static void init_chapter(void) {
    handle_pending_switch();
    struct rebinding rb[] = {
        {"exit",  (void*)hook_exit,  (void**)&libc_exit},
        {"_exit", (void*)hook__exit, (void**)&libc__exit},
    };
    rebind_symbols(rb, 2);
    start_temp_poller();
}

__attribute__((constructor(101))) static void init_probe(void) { installProbeHooks(); }

static BOOL handle_open_url(id self, SEL _cmd, UIApplication *app, NSURL *url, NSDictionary *opts) {
    write_log("[openURL] %s", [[url absoluteString] UTF8String]);
    return YES;
}

__attribute__((constructor(104))) static void init_url_scheme(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"iPad_RunnerAppDelegate");
        if (!cls) return;
        SEL sel = @selector(application:openURL:options:);
        if (!class_getInstanceMethod(cls, sel)) {
            class_addMethod(cls, sel, (IMP)handle_open_url, "B@:@@@");
            write_log("[URLScheme] openURL:options: added");
        }
    });
}

void minimalfunction() {}