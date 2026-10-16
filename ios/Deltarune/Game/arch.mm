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

static void (*orig_exit_fn)(int);
static void (*orig__exit_fn)(int);
static int g_exiting = 0;

static void applyChapterSwitch(void) {
    @autoreleasepool {
        NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docPaths.count == 0) return;
        NSString *docsDir = docPaths[0];
        NSFileManager *fm = [NSFileManager defaultManager];

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

        if (triggerFile == nil) return;

        NSLog(@"[ChapterSwitch] Detected %@, target chapter %d", triggerFile, chapterNum);

        setTargetChapter(chapterNum);

        NSString *triggerPath = [docsDir stringByAppendingPathComponent:triggerFile];
        NSError *err = nil;
        [fm removeItemAtPath:triggerPath error:&err];
        if (err) {
            NSLog(@"[ChapterSwitch] Failed to delete trigger file: %@", err);
        }
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

        if (pending) {
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

__attribute__((constructor(100))) static void chapterSwitchInit(void) {
    applyChapterSwitch();
    struct rebinding rb[] = {
        {"exit",  (void*)my_exit,  (void**)&orig_exit_fn},
        {"_exit", (void*)my__exit, (void**)&orig__exit_fn},
    };
    rebind_symbols(rb, 2);
}

__attribute__((constructor(101))) static void probeInitConstructor(void) {
    installProbeHooks();
}

void minimalfunction()
{
}