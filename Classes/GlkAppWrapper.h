//
//  GlkAppWrapper.h
//  IosGlk
//
//  Created by Andrew Plotkin on 1/28/11.
//  Copyright 2011 Andrew Plotkin. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "glk.h"

@interface GlkAppWrapper : NSObject {
	BOOL iowait; /* true when waiting for an event; becomes false when one arrives */
	NSCondition *iowaitcond;
	NSThread *thread;
	NSAutoreleasePool *looppool;
	
	NSNumber *timerinterval;
}

@property (nonatomic, retain) NSCondition *iowaitcond;
@property BOOL iowait; /* atomic */
@property (nonatomic, retain) NSNumber *timerinterval;

+ (GlkAppWrapper *) singleton;

- (void) launchAppThread;
- (void) appThreadMain:(id)rock;
- (void) selectEvent:(event_t *)event;
- (void) acceptEventType:(glui32)type window:(GlkWindow *)win val1:(glui32)val1 val2:(glui32)val2;
- (void) setTimerInterval:(NSNumber *)interval;
- (void) fireTimer:(id)dummy;

@end
