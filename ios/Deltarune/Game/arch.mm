//
//  arch.mm
//  Deltarune
//
//  Chapter switching support via select_chapter_N file detection.
//  On app launch (before main), checks Documents directory for select_chapter_N.
//  If found, swaps game data files and deletes the trigger file.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static void applyChapterSwitch(void) {
    @autoreleasepool {
        NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docPaths.count == 0) return;
        NSString *docsDir = docPaths[0];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

        // Scan for select_chapter_N files (N = 0-9)
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

        NSLog(@"[ChapterSwitch] Detected %@, switching to chapter %d", triggerFile, chapterNum);

        NSString *gameDroidDest = [docsDir stringByAppendingPathComponent:@"game.droid"];
        NSString *audioDest = [docsDir stringByAppendingPathComponent:@"audiogroup1.dat"];

        if (chapterNum == 0) {
            // Chapter 0: revert to bundle defaults by removing overrides in Documents
            NSError *err = nil;
            if ([fm fileExistsAtPath:gameDroidDest]) {
                [fm removeItemAtPath:gameDroidDest error:&err];
                if (err) NSLog(@"[ChapterSwitch] Failed to remove game.droid: %@", err);
            }
            if ([fm fileExistsAtPath:audioDest]) {
                [fm removeItemAtPath:audioDest error:&err];
                if (err) NSLog(@"[ChapterSwitch] Failed to remove audiogroup1.dat: %@", err);
            }
            NSLog(@"[ChapterSwitch] Reverted to bundle defaults (chapter 0)");
        } else {
            // Chapter N (1-9): copy gam{N}.droid -> Documents/game.droid
            NSString *gamSrcName = [NSString stringWithFormat:@"gam%d.droid", chapterNum];
            NSString *gamSrcPath = [bundlePath stringByAppendingPathComponent:gamSrcName];
            if (![fm fileExistsAtPath:gamSrcPath]) {
                NSLog(@"[ChapterSwitch] ERROR: %@ not found in bundle", gamSrcName);
            } else {
                NSError *err = nil;
                if ([fm fileExistsAtPath:gameDroidDest]) {
                    [fm removeItemAtPath:gameDroidDest error:nil];
                }
                [fm copyItemAtPath:gamSrcPath toPath:gameDroidDest error:&err];
                if (err) {
                    NSLog(@"[ChapterSwitch] Failed to copy %@: %@", gamSrcName, err);
                } else {
                    NSLog(@"[ChapterSwitch] Copied %@ -> Documents/game.droid", gamSrcName);
                }
            }

            // Copy audio{N}roup1.dat -> Documents/audiogroup1.dat
            NSString *audioSrcName = [NSString stringWithFormat:@"audio%droup1.dat", chapterNum];
            NSString *audioSrcPath = [bundlePath stringByAppendingPathComponent:audioSrcName];
            if (![fm fileExistsAtPath:audioSrcPath]) {
                NSLog(@"[ChapterSwitch] WARNING: %@ not found in bundle, skipping audio", audioSrcName);
            } else {
                NSError *err = nil;
                if ([fm fileExistsAtPath:audioDest]) {
                    [fm removeItemAtPath:audioDest error:nil];
                }
                [fm copyItemAtPath:audioSrcPath toPath:audioDest error:&err];
                if (err) {
                    NSLog(@"[ChapterSwitch] Failed to copy %@: %@", audioSrcName, err);
                } else {
                    NSLog(@"[ChapterSwitch] Copied %@ -> Documents/audiogroup1.dat", audioSrcName);
                }
            }
        }

        // Delete the trigger file
        NSString *triggerPath = [docsDir stringByAppendingPathComponent:triggerFile];
        NSError *err = nil;
        [fm removeItemAtPath:triggerPath error:&err];
        if (err) {
            NSLog(@"[ChapterSwitch] Failed to delete trigger file: %@", err);
        } else {
            NSLog(@"[ChapterSwitch] Deleted trigger file %@", triggerFile);
        }
    }
}

__attribute__((constructor)) static void chapterSwitchInit(void) {
    applyChapterSwitch();
}

void minimalfunction()
{
}
