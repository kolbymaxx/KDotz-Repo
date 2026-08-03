#import "GAAgentOrchestrator.h"
#import "GAGrokClient.h"
#import "GADeviceControl.h"
#import "GAToolRegistry.h"
#import "GAPreferences.h"
#import "GACommon.h"

static NSString *const kGASystemPrompt =
@"You are GrokAgent, an AI assistant that runs inside a jailbroken iPhone and can "
@"actually operate it. You are not a chatbot describing steps — you take them.\n\n"
@"Rules:\n"
@"1. Before acting on an unfamiliar screen, call describe_screen to see where you are.\n"
@"2. Prefer tap_element over tap_screen; labels survive layout changes, coordinates do not.\n"
@"3. Take one action at a time, then re-observe. Do not assume an action worked.\n"
@"4. To type: tap the field, then input_text.\n"
@"5. Stop and reply in plain language as soon as the task is done, or if you need "
@"information only the user has.\n"
@"6. Never take a destructive or irreversible action (deleting data, sending money, "
@"messaging someone) without saying what you are about to do and being told to proceed.\n"
@"7. Keep spoken replies to one or two sentences.";

@interface GAAgentOrchestrator ()
@property (nonatomic, readwrite) GAAgentState state;
@property (nonatomic, readwrite) BOOL isRunning;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *messages;
@property (nonatomic) NSInteger step;
@property (nonatomic) BOOL cancelled;
@end

@implementation GAAgentOrchestrator

+ (instancetype)shared {
    static GAAgentOrchestrator *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

#pragma mark - State

- (void)setState:(GAAgentState)state {
    _state = state;
    if ([self.observer respondsToSelector:@selector(agentDidChangeState:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self.observer agentDidChangeState:state]; });
    }
}

- (void)note:(NSString *)description {
    GALog(@"%@", description);
    if ([self.observer respondsToSelector:@selector(agentDidPerformStep:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self.observer agentDidPerformStep:description]; });
    }
}

- (void)finishWithReply:(NSString *)reply error:(NSError *)error {
    self.isRunning = NO;
    self.state = GAAgentStateIdle;
    if (error) GAErr(@"agent finished with error: %@", error.localizedDescription);
    if ([self.observer respondsToSelector:@selector(agentDidFinishWithReply:error:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.observer agentDidFinishWithReply:reply ?: @"" error:error];
        });
    }
}

#pragma mark - Loop

- (void)runWithPrompt:(NSString *)prompt {
    if (self.isRunning) {
        [self note:@"agent already running — ignoring new prompt"];
        return;
    }
    if (!prompt.length) return;

    self.isRunning = YES;
    self.cancelled = NO;
    self.step = 0;
    self.messages = [@[
        @{@"role": @"system", @"content": kGASystemPrompt},
        @{@"role": @"user",   @"content": prompt},
    ] mutableCopy];

    [self note:[NSString stringWithFormat:@"prompt: %@", prompt]];

    [[GADeviceControl shared] checkHealth:^(BOOL ok, NSString *version) {
        if (!ok) {
            [self finishWithReply:nil error:[NSError errorWithDomain:kGAIdentifier code:503
                userInfo:@{NSLocalizedDescriptionKey:
                    @"Device control backend is not reachable. Is iOS MCP installed and running?"}]];
            return;
        }
        [self tick];
    }];
}

- (void)cancel {
    self.cancelled = YES;
    [self note:@"cancelled"];
}

- (void)tick {
    if (self.cancelled) { [self finishWithReply:@"Stopped." error:nil]; return; }

    NSInteger budget = [GAPreferences shared].maxSteps;
    if (self.step >= budget) {
        [self finishWithReply:nil error:[NSError errorWithDomain:kGAIdentifier code:-6
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Gave up after %ld steps.", (long)budget]}]];
        return;
    }
    self.step++;
    self.state = GAAgentStateThinking;

    [[GAGrokClient shared] completeWithMessages:self.messages
                                          tools:[GAToolRegistry toolSchemas]
                                     completion:^(NSDictionary *message, NSError *error) {
        if (error) { [self finishWithReply:nil error:error]; return; }

        [self.messages addObject:message];

        NSArray *toolCalls = message[@"tool_calls"];
        if (![toolCalls isKindOfClass:[NSArray class]] || toolCalls.count == 0) {
            // No tools requested — the model is done talking.
            [self finishWithReply:message[@"content"] error:nil];
            return;
        }

        self.state = GAAgentStateActing;
        [self executeToolCalls:toolCalls atIndex:0];
    }];
}

/// Tool calls run sequentially: each one changes the device state the next one sees.
- (void)executeToolCalls:(NSArray *)toolCalls atIndex:(NSUInteger)index {
    if (self.cancelled) { [self finishWithReply:@"Stopped." error:nil]; return; }

    if (index >= toolCalls.count) { [self tick]; return; }

    NSDictionary *call = toolCalls[index];
    NSString *callID   = call[@"id"];
    NSString *name     = call[@"function"][@"name"];
    NSString *argsJSON = call[@"function"][@"arguments"] ?: @"{}";

    NSDictionary *args = [NSJSONSerialization JSONObjectWithData:
                          [argsJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![args isKindOfClass:[NSDictionary class]]) args = @{};

    void (^recordResult)(NSString *) = ^(NSString *text) {
        [self.messages addObject:@{
            @"role": @"tool",
            @"tool_call_id": callID ?: @"",
            @"content": text ?: @"",
        }];
        [self executeToolCalls:toolCalls atIndex:index + 1];
    };

    if (![GAToolRegistry isToolAllowed:name]) {
        [self note:[NSString stringWithFormat:@"blocked disallowed tool: %@", name]];
        recordResult([NSString stringWithFormat:
            @"Error: the tool '%@' is not available. Use one of the tools you were given.", name]);
        return;
    }

    [self note:[NSString stringWithFormat:@"→ %@ %@", name, args]];

    [[GADeviceControl shared] callTool:name arguments:args completion:^(NSString *result, NSError *error) {
        if (error) {
            recordResult([NSString stringWithFormat:@"Error: %@", error.localizedDescription]);
        } else {
            recordResult(result.length ? result : @"OK");
        }
    }];
}

@end
