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

static void (*orig_exit_fn)(int);
static void (*orig__exit_fn)(int);
static int g_exiting = 0;
static dispatch_source_t g_pollTimer = nil;

static void writeArchLog(const char *fmt, ...) {
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

        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^select_chapter_(\\d+)$"
                                                                               options:0
                                                                                 error:nil];
        NSArray *docFiles = [fm contentsOfDirectoryAtPath:docsDir error:nil];
        if (docFiles == nil) return;

        NSString *triggerFile = nil;
        int chapterNum = -1;
        for (NSString *fileName in docFiles) {
            NSTextCheckingResult *match = [regex firstMatchInString:fileName
                                                            options:0
                                                              range:NSMakeRange(0, fileName.length)];
            if (match) {
                NSRange numRange = [match rangeAtIndex:1];
                NSString *numStr = [fileName substringWithRange:numRange];
                int n = [numStr intValue];
                if (n >= 0 && n <= 9) {
                    triggerFile = fileName;
                    chapterNum = n;
                    break;
                }
            }
        }

        if (triggerFile == nil) {
            writeArchLog("[applyChapterSwitch] no trigger");
            return;
        }

        setTargetChapter(chapterNum);
        writeArchLog("[applyChapterSwitch] found %s chapter %d", [triggerFile UTF8String], chapterNum);

        NSString *triggerPath = [docsDir stringByAppendingPathComponent:triggerFile];
        [fm removeItemAtPath:triggerPath error:nil];
    }
}

static void handleExitBefore(void) {
    if (g_exiting) return;
    g_exiting = 1;

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
        if (!pending && [fm fileExistsAtPath:
            [docsDir stringByAppendingPathComponent:@"launcher.temp"]]) {
            pending = YES;
        }

        writeArchLog("[handleExitBefore] pending=%d", pending);
        if (pending) {
            writeArchLog("[handleExitBefore] openURL:dios://");
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication]
                    openURL:[NSURL URLWithString:@"dios://"]
                    options:@{}
                    completionHandler:nil];
            });
            usleep(500000);
        }
    }
}

static void my_exit(int code) {
    handleExitBefore();
    orig_exit_fn(code);
}

static void my__exit(int code) {
    handleExitBefore();
    orig__exit_fn(code);
}

static void startPoller(void) {
    if (g_pollTimer) return;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    g_pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(g_pollTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              300 * NSEC_PER_MSEC,
                              100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(g_pollTimer, ^{
        @autoreleasepool {
            if (g_exiting) return;
            NSArray *docs = NSSearchPathForDirectoriesInDomains(
                NSDocumentDirectory, NSUserDomainMask, YES);
            if (docs.count == 0) return;
            NSString *docDir = docs[0];
            NSFileManager *fm = [NSFileManager defaultManager];

            BOOL pending = NO;
            for (int i = 1; i <= 5; i++) {
                NSString *t = [docDir stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"select_chapter_%d", i]];
                if ([fm fileExistsAtPath:t]) { pending = YES; break; }
            }
            if (!pending && [fm fileExistsAtPath:
                [docDir stringByAppendingPathComponent:@"launcher.temp"]]) {
                pending = YES;
            }

            if (pending) {
                writeArchLog("[poller] trigger, exit(0)");
                exit(0);
            }
        }
    });
    dispatch_resume(g_pollTimer);
}

__attribute__((constructor(100))) static void chapterInit(void) {
    applyChapterSwitch();
    struct rebinding rb[] = {
        {"exit",  (void*)my_exit,  (void**)&orig_exit_fn},
        {"_exit", (void*)my__exit, (void**)&orig__exit_fn},
    };
    rebind_symbols(rb, 2);
    startPoller();
}

__attribute__((constructor(101))) static void probeInitConstructor(void) {
    installProbeHooks();
}

static BOOL dios_openURL(id self, SEL _cmd, UIApplication *app, NSURL *url, NSDictionary *opts) {
    writeArchLog("[openURL] %s", [[url absoluteString] UTF8String]);
    return YES;
}

__attribute__((constructor(104))) static void installURLHandler(void) {
    Class cls = NSClassFromString(@"iPad_RunnerAppDelegate");
    if (!cls) {
        writeArchLog("[URLScheme] class not found");
        return;
    }
    SEL sel = @selector(application:openURL:options:);
    if (!class_getInstanceMethod(cls, sel)) {
        class_addMethod(cls, sel, (IMP)dios_openURL, "B@:@@@");
        writeArchLog("[URLScheme] openURL:options: added");
    } else {
        writeArchLog("[URLScheme] openURL:options: exists");
    }
}

void minimalfunction() {}