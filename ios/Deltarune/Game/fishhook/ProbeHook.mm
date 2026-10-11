#import "ProbeHook.h"
#import "fishhook.h"
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <dlfcn.h>
#include <errno.h>
#include <dirent.h>
#include <limits.h>

static BOOL g_verbose = NO;
static __thread int g_inHook = 0;
static NSLock *g_logLock = nil;
static NSString *g_logPath = nil;
static dispatch_once_t g_initOnce = 0;

static char g_bundleCStr[PATH_MAX] = {0};
static char g_sandboxCStr[PATH_MAX] = {0};
static size_t g_bundleLen = 0;
static size_t g_sandboxLen = 0;

static NSHashTable *g_skipDirs = nil;
static NSLock *g_skipLock = nil;

static void probeInit(void) {
    dispatch_once(&g_initOnce, ^{
        int savedInHook = g_inHook;
        g_inHook = 1;

        g_logLock = [[NSLock alloc] init];
        g_skipDirs = [NSHashTable hashTableWithOptions:NSPointerFunctionsOpaqueMemory |
                                                        NSPointerFunctionsOpaquePersonality];
        g_skipLock = [[NSLock alloc] init];

        NSString *bp = [[NSBundle mainBundle] bundlePath];
        NSString *bpSlash = [bp hasSuffix:@"/"] ? bp : [bp stringByAppendingString:@"/"];
        const char *bpCStr = [bpSlash fileSystemRepresentation];
        size_t bpLen = strlen(bpCStr);
        if (bpLen >= sizeof(g_bundleCStr)) {
            g_bundleLen = 0;
        } else {
            memset(g_bundleCStr, 0, sizeof(g_bundleCStr));
            memcpy(g_bundleCStr, bpCStr, bpLen);
            g_bundleLen = bpLen;
        }

        NSString *home = NSHomeDirectory();
        NSString *homeSlash = [home hasSuffix:@"/"] ? home : [home stringByAppendingString:@"/"];
        const char *homeCStr = [homeSlash fileSystemRepresentation];
        size_t homeLen = strlen(homeCStr);
        if (homeLen >= sizeof(g_sandboxCStr)) {
            g_sandboxLen = 0;
        } else {
            memset(g_sandboxCStr, 0, sizeof(g_sandboxCStr));
            memcpy(g_sandboxCStr, homeCStr, homeLen);
            g_sandboxLen = homeLen;
        }

        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docs = [paths firstObject];
        g_logPath = [docs stringByAppendingPathComponent:@"probe.log"];

        NSString *verboseFlag = [docs stringByAppendingPathComponent:@"probe_verbose"];
        g_verbose = (access([verboseFlag fileSystemRepresentation], F_OK) == 0);

        unlink([g_logPath fileSystemRepresentation]);

        g_inHook = savedInHook;
    });
}

static void probeLogRaw(const char *buf) {
    if (!g_logPath) return;
    size_t len = strlen(buf);
    [g_logLock lock];
    int fd = open([g_logPath fileSystemRepresentation],
                  O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (fd >= 0) { write(fd, buf, len); close(fd); }
    [g_logLock unlock];
}

static void probeLog(const char *fmt, ...) {
    if (g_inHook) return;
    g_inHook = 1;
    @autoreleasepool {
        if (!g_logPath) probeInit();
        if (g_logPath) {
            char buf[2048];
            va_list ap;
            va_start(ap, fmt);
            vsnprintf(buf, sizeof(buf), fmt, ap);
            va_end(ap);
            struct timeval tv;
            gettimeofday(&tv, NULL);
            char line[2400];
            snprintf(line, sizeof(line), "[%ld.%06d] %s\n",
                     (long)tv.tv_sec, (int)tv.tv_usec, buf);
            probeLogRaw(line);
        }
    }
    g_inHook = 0;
}

static const char* errnoStr(int e) {
    switch (e) {
        case 0:             return "OK";
        case ENOENT:        return "ENOENT";
        case EACCES:        return "EACCES";
        case EPERM:         return "EPERM";
        case EEXIST:        return "EEXIST";
        case ENOTDIR:       return "ENOTDIR";
        case EISDIR:        return "EISDIR";
        case ENOSPC:        return "ENOSPC";
        case EROFS:         return "EROFS";
        case EMFILE:        return "EMFILE";
        case ENFILE:        return "ENFILE";
        case EINVAL:        return "EINVAL";
        case ENAMETOOLONG:  return "ENAMETOOLONG";
        case EBADF:         return "EBADF";
        default:            return "?";
    }
}

static const char* accessModeStr(int amode) {
    if (amode == F_OK) return "F_OK";
    static __thread char buf[16];
    buf[0] = 0;
    if (amode & R_OK) strcat(buf, "R");
    if (amode & W_OK) strcat(buf, "W");
    if (amode & X_OK) strcat(buf, "X");
    return buf[0] ? buf : "?";
}

static BOOL isInBundle(const char* path) {
    if (!path || g_bundleLen == 0) return NO;
    if (strncmp(path, g_bundleCStr, g_bundleLen) == 0) return YES;
    size_t plen = strlen(path);
    if (plen + 1 == g_bundleLen && strncmp(path, g_bundleCStr, plen) == 0) return YES;
    return NO;
}

static BOOL isInSandbox(const char* path) {
    if (!path || g_sandboxLen == 0) return NO;
    if (strncmp(path, g_sandboxCStr, g_sandboxLen) == 0) return YES;
    size_t plen = strlen(path);
    if (plen + 1 == g_sandboxLen && strncmp(path, g_sandboxCStr, plen) == 0) return YES;
    return NO;
}

static BOOL isSystemPath(const char* path) {
    if (!path) return NO;
    if (path[0] != '/') return NO;
    if (isInBundle(path) || isInSandbox(path)) return NO;
    if (strncmp(path, "/System/", 8) == 0) return YES;
    if (strncmp(path, "/private/preboot/", 17) == 0) return YES;
    if (strncmp(path, "/usr/", 5) == 0) return YES;
    if (strncmp(path, "/Developer/", 11) == 0) return YES;
    if (strncmp(path, "/Applications/", 14) == 0) return YES;
    if (strncmp(path, "/dev/", 5) == 0) return YES;
    if (strstr(path, ".axbundle")) return YES;
    if (strstr(path, "/Artwork.bundle/")) return YES;
    if (strstr(path, "/DesignLibrary-iOS.bundle/")) return YES;
    return NO;
}

static BOOL shouldLog(const char* path) {
    if (g_verbose) return YES;
    if (!path) return YES;
    if (isSystemPath(path)) return NO;
    return YES;
}

static FILE* (*orig_fopen)(const char*, const char*);
static int   (*orig_open)(const char*, int, ...);
static int   (*orig_openat)(int, const char*, int, ...);
static int   (*orig_access)(const char*, int);
static int   (*orig_stat)(const char*, struct stat*);
static int   (*orig_lstat)(const char*, struct stat*);
static int   (*orig_unlink)(const char*);
static int   (*orig_rename)(const char*, const char*);
static int   (*orig_mkdir)(const char*, mode_t);
static void* (*orig_dlopen)(const char*, int);
static void* (*orig_dlsym)(void*, const char*);
static DIR*  (*orig_opendir)(const char*);
static struct dirent* (*orig_readdir)(DIR*);
static int   (*orig_closedir)(DIR*);
static int   (*orig_remove)(const char*);
static int   (*orig_rmdir)(const char*);
static int   (*orig_chdir)(const char*);

static FILE* my_fopen(const char* path, const char* mode) {
    if (g_inHook || !shouldLog(path)) return orig_fopen(path, mode);
    int savedErrno = errno;
    errno = 0;
    FILE* fp = orig_fopen(path, mode);
    int e = errno;
    if (!fp) {
        probeLog("fopen   %s [%s] => FAIL %s",
                 path ? path : "(null)", mode ? mode : "?", errnoStr(e));
    } else {
        BOOL writeOnly = mode && (strchr(mode, 'w') || strchr(mode, 'a')) && !strchr(mode, '+');
        if (writeOnly) {
            probeLog("fopen   %s [%s] => OK (write)",
                     path ? path : "(null)", mode ? mode : "?");
        } else {
            int fd = fileno(fp);
            long long size = -1;
            struct stat st;
            if (fd >= 0 && fstat(fd, &st) == 0) size = (long long)st.st_size;
            probeLog("fopen   %s [%s] => OK size=%lld",
                     path ? path : "(null)", mode ? mode : "?", size);
        }
    }
    errno = fp ? savedErrno : e;
    return fp;
}

static int my_open(const char* path, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list ap; va_start(ap, oflag);
        mode = va_arg(ap, int);
        va_end(ap);
    }
    if (g_inHook || !shouldLog(path)) {
        return (oflag & O_CREAT) ? orig_open(path, oflag, mode) : orig_open(path, oflag);
    }
    int savedErrno = errno;
    errno = 0;
    int ret = (oflag & O_CREAT) ? orig_open(path, oflag, mode) : orig_open(path, oflag);
    int e = errno;
    if (ret >= 0) probeLog("open    %s [0x%x] => OK fd=%d", path ? path : "(null)", oflag, ret);
    else          probeLog("open    %s [0x%x] => FAIL %s", path ? path : "(null)", oflag, errnoStr(e));
    errno = (ret >= 0) ? savedErrno : e;
    return ret;
}

static int my_openat(int dirfd, const char* path, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list ap; va_start(ap, oflag);
        mode = va_arg(ap, int);
        va_end(ap);
    }
    if (g_inHook || !shouldLog(path)) {
        return (oflag & O_CREAT) ? orig_openat(dirfd, path, oflag, mode) : orig_openat(dirfd, path, oflag);
    }
    int savedErrno = errno;
    errno = 0;
    int ret = (oflag & O_CREAT) ? orig_openat(dirfd, path, oflag, mode) : orig_openat(dirfd, path, oflag);
    int e = errno;
    if (ret >= 0) probeLog("openat  %d %s [0x%x] => OK fd=%d", dirfd, path ? path : "(null)", oflag, ret);
    else          probeLog("openat  %d %s [0x%x] => FAIL %s", dirfd, path ? path : "(null)", oflag, errnoStr(e));
    errno = (ret >= 0) ? savedErrno : e;
    return ret;
}

static int my_access(const char* path, int amode) {
    if (g_inHook || !shouldLog(path)) return orig_access(path, amode);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_access(path, amode);
    int e = errno;
    if (ret != 0) probeLog("access  %s [%s] => FAIL %s", path ? path : "(null)", accessModeStr(amode), errnoStr(e));
    else if (g_verbose) probeLog("access  %s [%s] => OK", path ? path : "(null)", accessModeStr(amode));
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

static int my_stat(const char* path, struct stat* buf) {
    if (g_inHook || !shouldLog(path)) return orig_stat(path, buf);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_stat(path, buf);
    int e = errno;
    if (ret != 0) probeLog("stat    %s => FAIL %s", path ? path : "(null)", errnoStr(e));
    else if (g_verbose && buf) probeLog("stat    %s => OK size=%lld", path ? path : "(null)", (long long)buf->st_size);
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

static int my_lstat(const char* path, struct stat* buf) {
    if (g_inHook || !shouldLog(path)) return orig_lstat(path, buf);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_lstat(path, buf);
    int e = errno;
    if (ret != 0) probeLog("lstat   %s => FAIL %s", path ? path : "(null)", errnoStr(e));
    else if (g_verbose && buf) probeLog("lstat   %s => OK size=%lld", path ? path : "(null)", (long long)buf->st_size);
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

static int my_unlink(const char* path) {
    if (g_inHook || !shouldLog(path)) return orig_unlink(path);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_unlink(path);
    int e = errno;
    probeLog("unlink  %s => %s", path ? path : "(null)", ret == 0 ? "OK" : errnoStr(e));
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

static int my_rename(const char* from, const char* to) {
    if (g_inHook || (!shouldLog(from) && !shouldLog(to))) return orig_rename(from, to);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_rename(from, to);
    int e = errno;
    probeLog("rename  %s -> %s => %s",
             from ? from : "(null)", to ? to : "(null)",
             ret == 0 ? "OK" : errnoStr(e));
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

static int my_mkdir(const char* path, mode_t mode) {
    if (g_inHook || !shouldLog(path)) return orig_mkdir(path, mode);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_mkdir(path, mode);
    int e = errno;
    probeLog("mkdir   %s => %s", path ? path : "(null)", ret == 0 ? "OK" : errnoStr(e));
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

static void* my_dlopen(const char* path, int mode) {
    if (g_inHook || !shouldLog(path)) return orig_dlopen(path, mode);
    int savedErrno = errno;
    void* ret = orig_dlopen(path, mode);
    if (!ret) probeLog("dlopen  %s => FAIL", path ? path : "(null)");
    else if (g_verbose) probeLog("dlopen  %s => OK", path ? path : "(null)");
    errno = savedErrno;
    return ret;
}

static void* my_dlsym(void* handle, const char* sym) {
    if (g_inHook) return orig_dlsym(handle, sym);
    int savedErrno = errno;
    void* ret = orig_dlsym(handle, sym);
    if (handle != NULL && sym && !ret) probeLog("dlsym   %s => NOT FOUND", sym);
    errno = savedErrno;
    return ret;
}

static DIR* my_opendir(const char* path) {
    if (g_inHook) return orig_opendir(path);

    BOOL logIt = shouldLog(path);
    BOOL skipEnum = isSystemPath(path);

    int savedErrno = errno;
    errno = 0;
    DIR* d = orig_opendir(path);
    int e = errno;

    if (d && skipEnum && g_skipDirs) {
        [g_skipLock lock];
        [g_skipDirs addObject:(__bridge id)d];
        [g_skipLock unlock];
    }

    if (logIt) {
        probeLog("opendir %s => %s",
                 path ? path : "(null)",
                 d ? "OK" : errnoStr(e));
    }

    errno = d ? savedErrno : e;
    return d;
}

static struct dirent* my_readdir(DIR* d) {
    if (g_inHook) return orig_readdir(d);
    struct dirent* ent = orig_readdir(d);
    int e = errno;
    if (g_verbose && ent) {
        BOOL skip = NO;
        if (d && g_skipDirs) {
            [g_skipLock lock];
            skip = [g_skipDirs containsObject:(__bridge id)d];
            [g_skipLock unlock];
        }
        if (!skip) probeLog("  ... %s", ent->d_name);
    }
    errno = e;
    return ent;
}

static int my_closedir(DIR* d) {
    int savedErrno = errno;
    if (d && g_skipDirs) {
        [g_skipLock lock];
        [g_skipDirs removeObject:(__bridge id)d];
        [g_skipLock unlock];
    }
    errno = savedErrno;
    return orig_closedir(d);
}

static int my_remove(const char* path) {
    if (g_inHook || !shouldLog(path)) return orig_remove(path);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_remove(path);
    int e = errno;
    probeLog("remove  %s => %s", path ? path : "(null)", ret == 0 ? "OK" : errnoStr(e));
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

static int my_rmdir(const char* path) {
    if (g_inHook || !shouldLog(path)) return orig_rmdir(path);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_rmdir(path);
    int e = errno;
    probeLog("rmdir   %s => %s", path ? path : "(null)", ret == 0 ? "OK" : errnoStr(e));
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

static int my_chdir(const char* path) {
    if (g_inHook || !shouldLog(path)) return orig_chdir(path);
    int savedErrno = errno;
    errno = 0;
    int ret = orig_chdir(path);
    int e = errno;
    probeLog("chdir   %s => %s", path ? path : "(null)", ret == 0 ? "OK" : errnoStr(e));
    errno = (ret == 0) ? savedErrno : e;
    return ret;
}

void installProbeHooks(void) {
    probeInit();
    probeLog("PROBE bundle=%s", g_bundleCStr);
    probeLog("PROBE sandbox=%s", g_sandboxCStr);
    probeLog("PROBE verbose=%s", g_verbose ? "YES" : "NO");

    struct rebinding rb[] = {
        {(char*)"fopen",    (void*)my_fopen,    (void**)&orig_fopen},
        {(char*)"open",     (void*)my_open,     (void**)&orig_open},
        {(char*)"openat",   (void*)my_openat,   (void**)&orig_openat},
        {(char*)"access",   (void*)my_access,   (void**)&orig_access},
        {(char*)"stat",     (void*)my_stat,     (void**)&orig_stat},
        {(char*)"lstat",    (void*)my_lstat,    (void**)&orig_lstat},
        {(char*)"unlink",   (void*)my_unlink,   (void**)&orig_unlink},
        {(char*)"rename",   (void*)my_rename,   (void**)&orig_rename},
        {(char*)"mkdir",    (void*)my_mkdir,    (void**)&orig_mkdir},
        {(char*)"dlopen",   (void*)my_dlopen,   (void**)&orig_dlopen},
        {(char*)"dlsym",    (void*)my_dlsym,    (void**)&orig_dlsym},
        {(char*)"opendir",  (void*)my_opendir,  (void**)&orig_opendir},
        {(char*)"readdir",  (void*)my_readdir,  (void**)&orig_readdir},
        {(char*)"closedir", (void*)my_closedir, (void**)&orig_closedir},
        {(char*)"remove",   (void*)my_remove,   (void**)&orig_remove},
        {(char*)"rmdir",    (void*)my_rmdir,    (void**)&orig_rmdir},
        {(char*)"chdir",    (void*)my_chdir,    (void**)&orig_chdir},
    };
    int n = sizeof(rb) / sizeof(rb[0]);
    int result = rebind_symbols(rb, n);
    if (result == 0) {
        probeLog("PROBE rebind(%d) OK", n);
    } else {
        probeLog("PROBE rebind(%d) FAILED (code=%d), hooks may be partial", n, result);
    }
}