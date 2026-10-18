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
#include <unistd.h>
#include <objc/runtime.h>
#include <signal.h>

static void (*libc_exit)(int);
static void (*libc__exit)(int);
static int is_exiting = 0;
static dispatch_source_t poller_timer = nil;

static void write_log(const char *fmt, ...) {
    @autoreleasepool {
        NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docs.count == 0) return;
        NSString *path = [docs[0] stringByAppendingPathComponent:@"arch.log"];
        FILE *f = fopen([path UTF8String], "a");
        if (!f) return;
        va_list ap;
        va_start(ap, fmt);
        vfprintf(f, fmt, ap);
        va_end(ap);
        fprintf(f, "\n");
        fclose(f);
    }
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
            write_log("[switch] launcher");
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
                    write_log("[switch] target %d", n);
                    [fm removeItemAtPath:[docsDir stringByAppendingPathComponent:fileName] error:nil];
                    return;
                }
            }
        }
    }
}

static void check_pending_before_exit(void) {
    if (is_exiting) return;
    is_exiting = 1;

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
        if (!pending && [fm fileExistsAtPath:[docsDir stringByAppendingPathComponent:@"quit.temp"]]) {
            pending = YES;
        }

        if (pending) {
            write_log("[exit] openURL");
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"dios://"] options:@{} completionHandler:nil];
            });
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
        }
    }
}

static void hook_exit(int code) {
    check_pending_before_exit();
    libc_exit(code);
}

static void hook__exit(int code) {
    check_pending_before_exit();
    libc__exit(code);
}

static void start_temp_poller(void) {
    if (poller_timer) return;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    poller_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    
    dispatch_source_set_timer(poller_timer, dispatch_time(DISPATCH_TIME_NOW, 0), 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
    
    dispatch_source_set_event_handler(poller_timer, ^{
        @autoreleasepool {
            if (is_exiting) return;
            NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            if (docs.count == 0) return;
            NSString *docDir = docs[0];
            NSFileManager *fm = [NSFileManager defaultManager];

            BOOL pending = NO;
            for (int i = 1; i <= 5; i++) {
                NSString *t = [docDir stringByAppendingPathComponent:[NSString stringWithFormat:@"select_chapter_%d", i]];
                if ([fm fileExistsAtPath:t]) { pending = YES; break; }
            }
            if (!pending && [fm fileExistsAtPath:[docDir stringByAppendingPathComponent:@"launcher.temp"]]) {
                pending = YES;
            }
            if (!pending && [fm fileExistsAtPath:[docDir stringByAppendingPathComponent:@"quit.temp"]]) {
                pending = YES;
            }

            if (pending) {
                is_exiting = 1;
                dispatch_async(dispatch_get_main_queue(), ^{
                    write_log("[poller] main thread restart");
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"dios://"] options:@{} completionHandler:nil];
                    usleep(200000);
                    kill(getpid(), SIGKILL);
                });
            }
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

__attribute__((constructor(101))) static void init_probe(void) {
    installProbeHooks();
}

static BOOL handle_open_url(id self, SEL _cmd, UIApplication *app, NSURL *url, NSDictionary *opts) {
    write_log("[openURL] %s", [[url absoluteString] UTF8String]);
    return YES;
}

__attribute__((constructor(104))) static void init_url_scheme(void) {
    Class cls = NSClassFromString(@"iPad_RunnerAppDelegate");
    if (!cls) return;
    SEL sel = @selector(application:openURL:options:);
    if (!class_getInstanceMethod(cls, sel)) {
        class_addMethod(cls, sel, (IMP)handle_open_url, "B@:@@@");
    }
}

void minimalfunction() {}