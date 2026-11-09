#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <MobileGestalt/MobileGestalt.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>
#import <substrate.h>
#import <objc/runtime.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#define VISIONKIT_CORE_PATH "/System/Library/PrivateFrameworks/VisionKitCore.framework/VisionKitCore"

static MSImageRef visionKitImage;
static void (*vk_deviceSupportsImageAnalysis_block_invoke)(void);

// VisionKitCore keeps this flag as a local Mach-O symbol, so dlsym cannot find it.
// Resolve it from the loaded image's symbol table and fail closed if the layout differs.
static void *FindReadableSymbol(MSImageRef image, const char *wantedName) {
    if (!image || !wantedName) return NULL;

    const struct mach_header_64 *header = (const struct mach_header_64 *)image;
    if (header->magic != MH_MAGIC_64) return NULL;

    const struct symtab_command *symtab = NULL;
    const struct segment_command_64 *linkedit = NULL;
    const uint8_t *commandBytes = (const uint8_t *)(header + 1);

    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *command = (const struct load_command *)commandBytes;
        if (command->cmdsize < sizeof(struct load_command)) return NULL;

        if (command->cmd == LC_SYMTAB && command->cmdsize >= sizeof(struct symtab_command)) {
            symtab = (const struct symtab_command *)command;
        } else if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) {
                linkedit = segment;
            }
        }

        commandBytes += command->cmdsize;
    }

    if (!symtab || !linkedit) return NULL;

    intptr_t slide = 0;
    BOOL imageIsLoaded = NO;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (_dyld_get_image_header(i) == (const struct mach_header *)header) {
            slide = _dyld_get_image_vmaddr_slide(i);
            imageIsLoaded = YES;
            break;
        }
    }
    if (!imageIsLoaded) return NULL;

    uintptr_t linkeditBase = (uintptr_t)((intptr_t)linkedit->vmaddr + slide - (intptr_t)linkedit->fileoff);
    if (symtab->symoff == 0 || symtab->stroff == 0) return NULL;

    const struct nlist_64 *symbols = (const struct nlist_64 *)(linkeditBase + symtab->symoff);
    const char *strings = (const char *)(linkeditBase + symtab->stroff);

    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        uint32_t stringIndex = symbols[i].n_un.n_strx;
        if (stringIndex == 0 || stringIndex >= symtab->strsize) continue;
        if (symbols[i].n_type & N_STAB) continue;
        if (strcmp(strings + stringIndex, wantedName) != 0) continue;

        uint8_t type = symbols[i].n_type & N_TYPE;
        if (type != N_SECT && type != N_ABS) return NULL;

        intptr_t address = (intptr_t)symbols[i].n_value;
        if (type != N_ABS) address += slide;
        return (void *)address;
    }

    return NULL;
}

%hook PXVisualIntelligenceManager

+ (BOOL)isVisualSearchSupported {
    return YES;
}

%end

%group Camera

%hook CAMCaptureCapabilities

- (BOOL)isImageAnalysisSupported {
    return YES;
}

%end

%end

static void InstallCameraHook(void) {
    if (objc_getClass("CAMCaptureCapabilities")) {
        %init(Camera);
    }
}

%group VisionKitCore

%hookf(void, vk_deviceSupportsImageAnalysis_block_invoke) {
    %orig;

    static bool *supportsWithOverride = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        supportsWithOverride = (bool *)FindReadableSymbol(
            visionKitImage,
            "_vk_deviceSupportsImageAnalysis._supportsWithOverride"
        );
    });

    if (supportsWithOverride) {
        *supportsWithOverride = true;
    }
}

%end

%group MobileGestalt

%hookf(bool, MGGetBoolAnswer, CFStringRef question) {
    if (question && CFStringCompare(question, CFSTR("+N9mZUAHooNvMiQnjeTJ8g"), 0) == kCFCompareEqualTo) {
        return true;
    }
    return %orig;
}

%end

static void InstallMobileGestaltHook(void) {
    %init(MobileGestalt);
}

static const void *internationalSettingsObserver = &internationalSettingsObserver;
static const void *cameraSettingsObserver = &cameraSettingsObserver;

static void InternationalSettingsBundleLoaded(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (!objc_getClass("InternationalSettingsController")) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        InstallMobileGestaltHook();
        CFNotificationCenterRemoveObserver(center, internationalSettingsObserver, name, object);
    });
}

static void CameraSettingsBundleLoaded(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (!objc_getClass("CameraSettingsController")) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        InstallCameraHook();
        CFNotificationCenterRemoveObserver(center, cameraSettingsObserver, name, object);
    });
}

FOUNDATION_EXPORT char ***_NSGetArgv(void);

%ctor {
    %init;

    NSString *executablePath = [NSString stringWithUTF8String:**_NSGetArgv()];
    NSString *processName = executablePath.lastPathComponent;

    if ([processName isEqualToString:@"Camera"]) {
        InstallCameraHook();
    }

    dlopen(VISIONKIT_CORE_PATH, RTLD_LAZY);
    visionKitImage = MSGetImageByName(VISIONKIT_CORE_PATH);
    if (visionKitImage) {
        vk_deviceSupportsImageAnalysis_block_invoke = (void (*)(void))MSFindSymbol(
            visionKitImage,
            "___vk_deviceSupportsImageAnalysis_block_invoke"
        );
        if (vk_deviceSupportsImageAnalysis_block_invoke) {
            %init(VisionKitCore);
        }
    }

    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.Preferences"]) {
        InstallMobileGestaltHook();
        return;
    }

    CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
    CFStringRef bundleDidLoad = CFSTR("NSBundleDidLoadNotification");
    CFNotificationCenterAddObserver(
        center,
        internationalSettingsObserver,
        InternationalSettingsBundleLoaded,
        bundleDidLoad,
        (__bridge CFBundleRef)[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/InternationalSettings.bundle"],
        CFNotificationSuspensionBehaviorCoalesce
    );
    CFNotificationCenterAddObserver(
        center,
        cameraSettingsObserver,
        CameraSettingsBundleLoaded,
        bundleDidLoad,
        (__bridge CFBundleRef)[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/CameraSettings.bundle"],
        CFNotificationSuspensionBehaviorCoalesce
    );
}
