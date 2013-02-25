//
//  SEBWindowSizeValueTransformer.m
//  SafeExamBrowser
//
//  Created by Daniel R. Schneider on 25.02.13.
//
//

#import "SEBWindowSizeValueTransformer.h"

@implementation SEBWindowSizeValueTransformer


+ (Class)transformedValueClass
{
    return [NSNumber class];
}


+ (BOOL)allowsReverseTransformation
{
    return YES;
}


- (id)transformedValue:(id)value
{
    NSInteger *windowSize;
    
    if (value == nil) return nil;
    
    // Attempt to get a reasonable value from the
    // value object.
    if ([value isMemberOfClass:[NSString class]]) {
        
        if ([value isEqualToString:@"Screen"])
            windowSize = 0;
        else
            windowSize = [value integerValue];

    } else {
        [NSException raise: NSInternalInconsistencyException
                    format: @"Value (%@) is not member of class NSString.",
         [value class]];
    }
    return [NSNumber numberWithInteger:windowSize];
}


- (id)reverseTransformedValue:(id)value
{
    NSString *windowSize;
    
    if (value == nil) return nil;
    
    if ([value respondsToSelector: @selector(integerValue)]) {
        if (value == 0)
            windowSize = @"Screen";
        else
            windowSize = [value stringValue];
    } else {
        [NSException raise: NSInternalInconsistencyException
                    format: @"Value (%@) does not respond to -integerValue.",
         [value class]];
    }
    
    return windowSize;
}
@end
