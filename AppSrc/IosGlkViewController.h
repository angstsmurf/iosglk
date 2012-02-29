/* IosGlkViewController.h: Main view controller class
	for IosGlk, the iOS implementation of the Glk API.
	Designed by Andrew Plotkin <erkyrath@eblong.com>
	http://eblong.com/zarf/glk/
*/

#import <UIKit/UIKit.h>

@class GlkFrameView;
@class PopMenuView;
@class MoreBoxView;
@class GlkLibraryState;
@protocol IosGlkLibDelegate;

@interface IosGlkViewController : UIViewController {
	id <IosGlkLibDelegate> glkdelegate;
	GlkFrameView *frameview;

	/* Strings typed into input lines (across all windows) */
	NSMutableArray *commandhistory;	
}

@property (nonatomic, assign) IBOutlet id <IosGlkLibDelegate> glkdelegate; // delegates are nonretained
@property (nonatomic, retain) IBOutlet GlkFrameView *frameview;

@property (nonatomic, retain) NSMutableArray *commandhistory;	
@property (nonatomic, readonly) BOOL debug_updating_library;

+ (IosGlkViewController *) singleton;

- (void) didFinishLaunching;
- (void) becameInactive;
- (void) becameActive;
- (void) enteredBackground;
- (void) updateFromLibraryState:(GlkLibraryState *)library;

- (void) hideKeyboard;
- (void) displayModalRequest:(id)special;

- (void) buildPopMenu:(PopMenuView *)menuview;
- (void) buildMoreView:(MoreBoxView *)moreview;
- (IBAction) toggleKeyboard;
- (void) addToCommandHistory:(NSString *)str;

@end

