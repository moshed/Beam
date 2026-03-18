#import <Foundation/Foundation.h>

@interface ObjCExceptionCatcher : NSObject
+ (BOOL)catchException:(void(NS_NOESCAPE ^)(void))tryBlock;
@end
