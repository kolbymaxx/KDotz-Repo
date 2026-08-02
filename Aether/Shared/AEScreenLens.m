#import "AEScreenLens.h"
#import <Vision/Vision.h>

@implementation AEScreenLens

+ (UIImage *)snapshotWindow:(UIWindow *)window {
    if (!window) return nil;
    CGSize size = window.bounds.size;
    if (size.width < 1 || size.height < 1) return nil;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = MIN(window.screen.scale, 2.0); // keep OCR fast
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
    }];
}

+ (void)recognizeTextInWindow:(UIWindow *)window completion:(AEScreenLensCompletion)completion {
    UIImage *img = [self snapshotWindow:window];
    if (!img) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"Aether" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"Could not capture screen"}]);
        }
        return;
    }
    [self recognizeTextInImage:img completion:completion];
}

+ (void)recognizeTextInImage:(UIImage *)image completion:(AEScreenLensCompletion)completion {
    if (!image.CGImage) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"Aether" code:2
                                           userInfo:@{NSLocalizedDescriptionKey: @"Invalid image"}]);
        }
        return;
    }
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
    VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, error); });
            return;
        }
        NSMutableArray *lines = [NSMutableArray array];
        for (VNRecognizedTextObservation *obs in request.results) {
            VNRecognizedText *top = [[obs topCandidates:1] firstObject];
            if (top.string.length) [lines addObject:top.string];
        }
        NSString *joined = [lines componentsJoinedByString:@"\n"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(joined.length ? joined : nil, nil);
        });
    }];
    if (@available(iOS 15.0, *)) {
        req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        req.usesLanguageCorrection = YES;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        [handler performRequests:@[req] error:&err];
        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, err); });
        }
    });
}

@end
