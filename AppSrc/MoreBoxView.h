/* MoreBoxView.h: Base class for the "more" view
 for IosGlk, the iOS implementation of the Glk API.
 Designed by Andrew Plotkin <erkyrath@eblong.com>
 http://eblong.com/zarf/glk/
 */

#import <UIKit/UIKit.h>

@interface MoreBoxView : UIView {
	UIView *frameview;
}

@property (nonatomic, strong) IBOutlet UIView *frameview;

@end
