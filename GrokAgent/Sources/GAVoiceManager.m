#import "GAVoiceManager.h"
#import "GACommon.h"
#import <AVFoundation/AVFoundation.h>

@interface GAVoiceManager ()
@property (nonatomic, strong) AVSpeechSynthesizer *synth;
@end

@implementation GAVoiceManager

+ (instancetype)shared {
    static GAVoiceManager *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) _synth = [AVSpeechSynthesizer new];
    return self;
}

- (void)speak:(NSString *)text {
    if (!text.length) return;
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
    u.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
    u.rate = AVSpeechUtteranceDefaultSpeechRate;
    [self.synth speakUtterance:u];
    GALog(@"speaking: %@", text);
}

- (void)stopSpeaking {
    [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}

@end
