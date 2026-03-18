#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)catchException:(void(NS_NOESCAPE ^)(void))tryBlock {
    @try {
        tryBlock();
        return YES;
    }
    @catch (NSException *exception) {
        return NO;
    }
}

@end
