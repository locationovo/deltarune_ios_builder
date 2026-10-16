#import "fishhook/fishhook.h"
#import <Foundation/Foundation.h>
#include <string.h>
#include <limits.h>
#include <stdio.h>

static int g_target_chapter = 0;

void setTargetChapter(int chapter) {
    g_target_chapter = chapter;
}

static FILE* (*redir_orig_fopen)(const char*, const char*);

static FILE* redir_my_fopen(const char* path, const char* mode) {
    if (!path || !mode || mode[0] != 'r') return redir_orig_fopen(path, mode);
    if (g_target_chapter <= 0) return redir_orig_fopen(path, mode);
    if (!strstr(path, "/games/")) return redir_orig_fopen(path, mode);

    static __thread char buffer[PATH_MAX];

    const char *pGame = strstr(path, "/games/game.ios");
    if (pGame && pGame[15] == 0) {
        size_t prefix = pGame - path;
        if (prefix + 32 < sizeof(buffer)) {
            memcpy(buffer, path, prefix);
            snprintf(buffer + prefix, sizeof(buffer) - prefix,
                     "/games/gam%d.droid", g_target_chapter);
            return redir_orig_fopen(buffer, mode);
        }
    }

    const char *pAudio = strstr(path, "/games/audiogroup1.dat");
    if (pAudio && pAudio[22] == 0 && g_target_chapter >= 2) {
        size_t prefix = pAudio - path;
        if (prefix + 32 < sizeof(buffer)) {
            memcpy(buffer, path, prefix);
            snprintf(buffer + prefix, sizeof(buffer) - prefix,
                     "/games/audio%droup1.dat", g_target_chapter);
            return redir_orig_fopen(buffer, mode);
        }
    }

    return redir_orig_fopen(path, mode);
}

__attribute__((constructor(103))) static void installRedirect(void) {
    struct rebinding rb[] = {
        {"fopen", (void*)redir_my_fopen, (void**)&redir_orig_fopen},
    };
    rebind_symbols(rb, 1);
}