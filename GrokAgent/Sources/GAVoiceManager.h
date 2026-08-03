#import <Foundation/Foundation.h>

/// Voice pipeline.
///
/// TTS works today — AVSpeechSynthesizer needs no entitlement.
///
/// STT is the open question. SFSpeechRecognizer inside SpringBoard needs
/// NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription in
/// SpringBoard's own Info.plist, which we do not control — so running our own
/// recognizer is the hard path.
///
/// The promising lead comes from Siri27: it rides Siri's audio pipeline with
/// no mic entitlement at all, hooking -[SUICOrbView setPowerLevel:] and
/// broadcasting the level cross-process over a Darwin notification. That proves
/// levels are reachable this way — not text — but Siri27 also already hooks
/// AFUISiriSession (-setState:), which lives IN the Siri process where a
/// recognized utterance would exist. If a transcript property hangs off that
/// session on 17.3, that is our STT for free: a Siri-process component that
/// forwards the transcript to SpringBoard the same way Siri27 forwards levels.
///
/// NEXT STEP before building the rest of the pipeline: class-dump
/// AFUISiriSession and AssistantServices on 17.3, look for a result /
/// transcription property. Fallbacks if it is not there, in order:
///   1. Helper app that owns the mic, pipes the transcript back over a socket.
///   2. Patch the usage-description strings into SpringBoard's plist at install
///      (fragile across updates, breaks on restore).
@interface GAVoiceManager : NSObject

+ (instancetype)shared;

- (void)speak:(NSString *)text;
- (void)stopSpeaking;

@end
