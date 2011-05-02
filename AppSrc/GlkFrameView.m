/* GlkFrameView.m: Main view class
	for IosGlk, the iOS implementation of the Glk API.
	Designed by Andrew Plotkin <erkyrath@eblong.com>
	http://eblong.com/zarf/glk/
*/

/*	GlkFrameView is the UIView which contains all of the Glk windows. (The GlkWindowViews are its children.) It is responsible for getting them all updated properly when the VM blocks for UI input.

	It's worth noting that all the content-y Glk windows have corresponding GlkWindowViews. But pair windows don't. They are abstractions which exist solely to calculate child window sizes.
*/

#import "GlkFrameView.h"
#import "IosGlkAppDelegate.h"
#import "IosGlkViewController.h"
#import "GlkWindowView.h"
#import "GlkWinBufferView.h"
#import "GlkAppWrapper.h"
#import "GlkLibrary.h"
#import "GlkWindow.h"
#import "Geometry.h"
#import "GlkUtilTypes.h"
#import "GlkUtilities.h"

@implementation GlkFrameView

@synthesize windowviews;
@synthesize wingeometries;
@synthesize rootwintag;

- (void) awakeFromNib {
	[super awakeFromNib];
	NSLog(@"GlkFrameView awakened, bounds %@", StringFromRect(self.bounds));

	keyboardHeight = 0.0;
	self.windowviews = [NSMutableDictionary dictionaryWithCapacity:8];
	self.wingeometries = [NSMutableDictionary dictionaryWithCapacity:8];
	rootwintag = nil;
}

- (void) dealloc {
	self.windowviews = nil;
	self.wingeometries = nil;
	self.rootwintag = nil;
	[super dealloc];
}

- (CGFloat) keyboardHeight {
	return keyboardHeight;
}

- (void) setKeyboardHeight:(CGFloat)val {
	keyboardHeight = val;
	//NSLog(@"### setKeyboardHeight calling setNeedsLayout");
	[self setNeedsLayoutPlusSubviews];
}

- (void) setNeedsLayoutPlusSubviews {
	[self setNeedsLayout];
	for (UIView *view in self.subviews) {
		[view setNeedsLayout];
	}
}

- (void) layoutSubviews {
	NSLog(@"frameview layoutSubviews to %@ (minus %.1f)", StringFromRect(self.bounds), keyboardHeight);
	
	CGRect box = self.bounds;
	box.size.height -= keyboardHeight;
	if (box.size.height < 0)
		box.size.height = 0;

	if (rootwintag) {
		/* We perform all of the frame-size-changing in a zero-length animation. Yes, I tried using setAnimationsEnabled:NO to turn off the animations entirely. But that spiked the WinBufferView's scrollToBottom animation. Sorry -- it makes no sense to me either. */
		[UIView beginAnimations:@"windowViewRearrange" context:nil];
		[UIView setAnimationDuration:0.0];
		[self windowViewRearrange:rootwintag rect:box];
		[UIView commitAnimations];
	}
	
	/* Now tell the VM thread. */
	[[GlkAppWrapper singleton] setFrameSize:box];
}

/* Set all the window view sizes, based on their cached geometry information. Note that this does not touch the GlkLibrary structures at all -- that could be under modification by the VM thread.

	(Small exception: this code looks at the Geometry objects, which are shared with GlkLibrary. That's okay because Geometry objects are immutable.)
*/
- (void) windowViewRearrange:(NSNumber *)tag rect:(CGRect)box {
	GlkWindowView *winv = [windowviews objectForKey:tag];
	Geometry *geometry = [wingeometries objectForKey:tag];
	
	/* Exactly one of winv and geom should be set here. (geom for pair windows, winv for all others.) */
	if (winv && geometry)
		[NSException raise:@"GlkException" format:@"view and geometry for same window"];
	if (!winv && !geometry)
		[NSException raise:@"GlkException" format:@"neither view and geometry for same window"];
	
	if (winv) {
		winv.frame = box;
		//NSLog(@"### setting frame for winview %@", winv);
	}
	else {
		CGRect box1;
		CGRect box2;
		NSNumber *ch1, *ch2;
		
		[geometry computeDivision:box for1:&box1 for2:&box2];

		if (!geometry.backward) {
			ch1 = geometry.child1tag;
			ch2 = geometry.child2tag;
		}
		else {
			ch1 = geometry.child2tag;
			ch2 = geometry.child1tag;
		}

		[self windowViewRearrange:ch1 rect:box1];
		[self windowViewRearrange:ch2 rect:box2];
	}
}

/* This tells all the window views to get up to date with the new output in their data (GlkWindow) objects. If window views have to be created or destroyed (because GlkWindows have opened or closed), this does that too.

	Called from selectEvent in the app wrapper class.
*/
- (void) updateFromLibraryState:(GlkLibrary *)library {
	NSLog(@"updateFromLibraryState: %@", StringFromRect(library.bounds));
	
	if (!library)
		[NSException raise:@"GlkException" format:@"updateFromLibraryState: no library"];
	
	/* Build a list of windowviews which need to be closed. */
	NSMutableDictionary *closed = [NSMutableDictionary dictionaryWithDictionary:windowviews];
	for (GlkWindow *win in library.windows) {
		[closed removeObjectForKey:win.tag];
	}

	/* And close them. */
	for (NSNumber *tag in closed) {
		GlkWindowView *winv = [closed objectForKey:tag];
		[winv removeFromSuperview];
		winv.textfield = nil; /* detach this now */
		//### probably should detach all subviews
		[windowviews removeObjectForKey:tag];
	}
	
	closed = nil;
	
	/* If there are any new windows, create windowviews for them. */
	for (GlkWindow *win in library.windows) {
		if (win.type != wintype_Pair && ![windowviews objectForKey:win.tag]) {
			GlkWindowView *winv = [GlkWindowView viewForWindow:win];
			[windowviews setObject:winv forKey:win.tag];
			[self addSubview:winv];
		}
	}
	
	/* If the window geometry has changed (windows created, deleted, or arrangement-set) then rebuild the geometry cache. */
	if (library.geometrychanged) {
		NSLog(@"Recaching window geometries");
		library.geometrychanged = NO;
		if (library.rootwin)
			self.rootwintag = library.rootwin.tag;
		else
			self.rootwintag = nil;
		[wingeometries removeAllObjects];
		for (GlkWindowPair *win in library.windows) {
			if (win.type == wintype_Pair) {
				Geometry *geom = [win.geometry copy];
				[wingeometries setObject:geom forKey:win.tag];
			}
		}
	}
	
	/*
	NSLog(@"frameview has %d windows:", windowviews.count);
	for (NSNumber *tag in windowviews) {
		NSLog(@"... %d: %@", [tag intValue], [windowviews objectForKey:tag]);
		//GlkWindowView *winv = [windowviews objectForKey:tag];
		//NSLog(@"... win is %@", winv.win);
	}
	*/

	/* Now go through all the window views, and tell them to update to match their windows. */
	for (NSNumber *tag in windowviews) {
		GlkWindowView *winv = [windowviews objectForKey:tag];
		[winv updateFromWindowState];
		[winv updateFromWindowInputs];
	}
	
	/* And now, if there's a special prompt going on, fill the screen with it. */
	if (library.specialrequest)
		[[IosGlkAppDelegate singleton].viewController displayModalRequest:library.specialrequest];
}

/* Query the main thread about what's in a particular window's input line. The VM thread calls this when it cancels line input and needs to know what in the input buffer.

	This is invoked in the main thread, by the VM thread, which is waiting on the result. We're safe from deadlock because the VM thread can't be in glk_select(); it can't be holding the iowait lock, and it can't get into the code path that rearranges the view structure.
*/
- (void) editingTextForWindow:(GlkTagString *)tagstring {
	GlkWindowView *winv = [windowviews objectForKey:tagstring.tag];
	if (!winv)
		return;
	
	UITextField *textfield = winv.textfield;
	if (!textfield)
		return;
		
	NSString *text = textfield.text;
	if (!text)
		return;
	
	/* The VM thread, when it picks this up, will take over the retention. */
	tagstring.str = [[NSString stringWithString:text] retain];
}

@end