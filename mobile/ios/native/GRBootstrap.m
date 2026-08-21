// gen1recomp iOS native bridge bootstrap.
//
// Runs the Files-app inbox sweep (GRPickerBridge.sweepInbox) every time the
// app becomes active, so ROMs/mods/saves dropped into the app's Documents
// folder land in the LÖVE save directory before the Lua importer rescans.
// Registered from a constructor so no LÖVE/SDL source needs to know about it.

#import <UIKit/UIKit.h>
#import <sys/utsname.h>

@interface GRDeviceBridge : NSObject
+ (NSString *)deviceModel;
@end

@implementation GRDeviceBridge
+ (NSString *)deviceModel
{
#if TARGET_OS_SIMULATOR
    NSString *simulatorModel = NSProcessInfo.processInfo.environment[@"SIMULATOR_MODEL_IDENTIFIER"];
    if (simulatorModel.length > 0) return simulatorModel;
#endif
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
        NSString *model = [NSString stringWithUTF8String:systemInfo.machine];
        if (model.length > 0) return model;
    }
    return @"";
}
@end

__attribute__((constructor))
static void GRBootstrapInstall(void)
{
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        Class bridge = NSClassFromString(@"GRPickerBridge");
        if ([bridge respondsToSelector:@selector(preparePublicDocuments)]) {
            [bridge performSelector:@selector(preparePublicDocuments)];
        }
        if ([bridge respondsToSelector:@selector(sweepInbox)]) {
            [bridge performSelector:@selector(sweepInbox)];
        }
    }];
}
