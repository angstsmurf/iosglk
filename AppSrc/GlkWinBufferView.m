/* GlkWinBufferView.m: Glk textbuffer window view
	for IosGlk, the iOS implementation of the Glk API.
	Designed by Andrew Plotkin <erkyrath@eblong.com>
	http://eblong.com/zarf/glk/
*/

#import "GlkWinBufferView.h"
#import "IosGlkAppDelegate.h"
#import "IosGlkViewController.h"
#import "GlkLibrary.h"
#import "GlkWindowState.h"
#import "GlkLibraryState.h"
#import "GlkUtilTypes.h"

#import "CmdTextField.h"
#import "MoreBoxView.h"
#import "StyleSet.h"
#import "GlkUtilities.h"
#import "GlkFrameView.h"

@implementation GlkWinBufferView

- (instancetype) initWithWindow:(GlkWindowState *)winref frame:(CGRect)box margin:(UIEdgeInsets)margin {
	self = [super initWithWindow:winref frame:box margin:margin];
	if (self) {
		self.contentMode = UIViewContentModeRedraw;
		self.backgroundColor = [UIColor clearColor];

		lastLayoutBounds = CGRectNull;
        self.textview =
        [[UITextView alloc] initWithFrame:self.bounds];
        _textview.translatesAutoresizingMaskIntoConstraints = NO;
        _textview.delegate = self;
        _textview.textContainerInset = margin;
        _textview.editable = NO;
        _textview.accessibilityTraits = UIAccessibilityTraitStaticText;

        [self addSubview:_textview];

        UILayoutGuide *margin = self.layoutMarginsGuide;

        [_textview.leadingAnchor constraintEqualToAnchor:margin.leadingAnchor].active = YES;
        [_textview.trailingAnchor constraintEqualToAnchor:margin.trailingAnchor].active = YES;
        [_textview.bottomAnchor constraintEqualToAnchor:margin.bottomAnchor].active = YES;
        [_textview.topAnchor constraintEqualToAnchor:margin.topAnchor].active = YES;

        textviewHeightConstraint = [_textview.heightAnchor constraintEqualToConstant:self.bounds.size.height];
        textviewHeightConstraint.active = YES;
//        textviewHeightEqualsSuperConstraint = [_textview.topAnchor constraintEqualToAnchor:margin.topAnchor];
//        textviewHeightEqualsSuperConstraint.active = YES;
//        textviewHeightEqualsTextConstraint = [_textview.heightAnchor constraintEqualToConstant:_textview.contentSize.height];
//        textviewHeightEqualsSuperConstraint.active = NO;

        IosGlkViewController *viewc = [IosGlkViewController singleton];
        UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:viewc action:@selector(textTapped:)];
        [_textview addGestureRecognizer:recognizer];
        recognizer.delegate = viewc;

		self.moreview = [[MoreBoxView alloc] initWithFrame:CGRectZero];
		[[NSBundle mainBundle] loadNibNamed:@"MoreBoxView" owner:_moreview options:nil];
		CGRect rect = _moreview.frameview.frame;
		rect.origin.x = MIN(box.size.width - self.viewmargin.right + 4, box.size.width - (rect.size.width + 4));
		rect.origin.y = box.size.height - (rect.size.height + 4);
		_moreview.frame = rect;
		[_moreview addSubview:_moreview.frameview];
		_moreview.userInteractionEnabled = NO;
		_moreview.hidden = YES;
		[self addSubview:_moreview];

        firstUpdate = YES;
        storedAtBottom = NO;
        storedAtTop = NO;
        inAnimatedScrollToBottom = NO;
        recursionDepth = 0;
        lastVisibleGlyph = 0;
	}
	return self;
}

- (void) dealloc {
	_textview.delegate = nil;
}

- (void) setViewmargin:(UIEdgeInsets)newmargin {
	super.viewmargin = newmargin;

	if (_textview) {
		[_textview setNeedsLayout];
		[_textview setNeedsDisplay];
	}
}

/* This is called when the GlkFrameView changes size, and also (in iOS4) when the child scrollview scrolls. This is a mysterious mix of cases, but we can safely ignore the latter by only acting when the bounds actually change.
*/
- (void) layoutSubviews {
	[super layoutSubviews];

//    if (self.superviewAsFrameView.inOrientationAnimation)
//        return;

	if (CGRectEqualToRect(lastLayoutBounds, self.bounds)) {
		return;
	}

    BOOL atBottom = ([self scrolledToBottom]);

	lastLayoutBounds = self.bounds;
	//NSLog(@"WBV: layoutSubviews to %@", StringFromRect(self.bounds));

	CGRect rect = _moreview.frameview.frame;
	rect.origin.x = MIN(lastLayoutBounds.size.width - self.viewmargin.right + 4, lastLayoutBounds.size.width - (rect.size.width + 4));
	rect.origin.y = lastLayoutBounds.size.height - (rect.size.height + 4);
	_moreview.frame = rect;

//    if (self.bounds.size.height > _textview.contentSize.height) {
//        textviewHeightConstraint.constant = _textview.contentSize.height;
//    } else {
//        textviewHeightConstraint.constant = self.bounds.size.height;
//    }

    if (atBottom && _textview.text.length) {
        [self scrollTextViewToBottomAnimate:NO];
    }

    if (self.inputfield)
        [self placeInputField:self.inputfield holder:self.inputholder];
}

- (void) uncacheLayoutAndStyles {
    BOOL atBottom = ([self scrolledToBottom]);
    /* reassign styles in the textstorage NSAttributedString */

    NSTextStorage *textstorage = _textview.textStorage;
    NSMutableAttributedString *backingStorage = [textstorage mutableCopy];

    NSArray<NSDictionary *> __block *blockStyles = self.styleset.bufferattributes;
    [textstorage
     enumerateAttributesInRange:NSMakeRange(0, textstorage.length)
     options:0
     usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        // We overwrite all attributes with those in the updated
        // styles array
        id styleobject = attrs[@"GlkStyle"];
        if (styleobject) {
            NSDictionary *stylesAtt = blockStyles[(NSUInteger)[styleobject intValue]];
            [backingStorage setAttributes:stylesAtt range:range];
        }
    }];

    [textstorage setAttributedString:backingStorage];

    if (self.inputfield) {
        [self.inputfield adjustForWindowStyles:self.styleset];
        [self placeInputField:self.inputfield holder:self.inputholder];
    }
	lastLayoutBounds = CGRectNull;
    if (atBottom) {
        [self scrollTextViewToBottomAnimate:NO];
    }
}

- (void) updateFromWindowState {
    GlkWindowBufferState *bufwin = (GlkWindowBufferState *)self.winstate;
    BOOL anychanges = NO;
    if (!bufwin.attrstring)
        bufwin.attrstring = [NSMutableAttributedString new];
    else if (bufwin.attrstring.length)
        anychanges = YES;

    NSTextStorage *textstorage = _textview.textStorage;

    if (![_textview.backgroundColor isEqual:bufwin.styleset.backgroundcolor]) {
        _textview.backgroundColor = bufwin.styleset.backgroundcolor;
        anychanges = YES;
    }
    UIEdgeInsets totalMargins = UIEdgeInsetsMake(bufwin.styleset.margins.top, bufwin.styleset.margins.left + self.viewmargin.left, bufwin.styleset.margins.bottom, bufwin.styleset.margins.right + self.viewmargin.right);
    if (!UIEdgeInsetsEqualToEdgeInsets(_textview.textContainerInset, totalMargins)) {
        _textview.textContainerInset = totalMargins;
        anychanges = YES;
    }

    if (_clearcount != bufwin.clearcount) {
        _clearcount = bufwin.clearcount;
        [textstorage setAttributedString:bufwin.attrstring];
        _lastSeenCharacterIndex = 0;
        anychanges = YES;
    } else {
        [textstorage appendAttributedString:bufwin.attrstring];
    }

    if (!anychanges)
        return;

    if (firstUpdate) {
        [self uncacheLayoutAndStyles];
    } else {
        /* Slightly awkward, but mostly right: if voiceover is on, speak the most recent buffer window update. */
        if (bufwin.attrstring.length &&
            UIAccessibilityIsVoiceOverRunning()) {
            NSString *toSpeak = bufwin.attrstring.string;
            // Don't speak the actual command
            NSRange stylerange;
            NSNumber *style = [bufwin.attrstring attribute:@"GlkStyle" atIndex:0 effectiveRange:&stylerange];
            if (style.integerValue == style_Input && NSMaxRange(stylerange) < toSpeak.length - 1)
                toSpeak = [toSpeak substringFromIndex:NSMaxRange(stylerange)];
            [self speakString:toSpeak];
        }
    }

    CGRect nextPage = CGRectZero;
    nextPage.size = self.bounds.size;
    nextPage.origin.y = _textview.contentOffset.y + nextPage.size.height;

    [_textview.layoutManager ensureLayoutForBoundingRect:nextPage inTextContainer:_textview.textContainer];

//    if (self.bounds.size.height > _textview.contentSize.height) {
//        textviewHeightConstraint.constant = _textview.contentSize.height;
//    } else {
//        textviewHeightConstraint.constant = self.bounds.size.height;
//    }

    [_textview setNeedsDisplay];

    if (!firstUpdate) {
        _nowcontentscrolling = YES;
        [_textview scrollRectToVisible:nextPage animated:YES];
    }
    firstUpdate = NO;
}

- (void)speakString:(NSString *)string {
    if (!string || string.length == 0) {
        return;
    }
    NSString *charSetString = @"\u00A0 >\n_";
    NSCharacterSet *charset = [NSCharacterSet characterSetWithCharactersInString:charSetString];
    string = [string stringByTrimmingCharactersInSet:charset];
    NSLog(@"speakString \"%@\"", string);
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, string);
    });
}

/* This is invoked whenever the user types something. If we're at a "more" prompt, it pages down once, and returns YES. Otherwise, it pages all the way to the bottom and returns NO.
 */
- (BOOL) pageDownOnInput {
    [self placeInputField:self.inputfield holder:self.inputholder];
	if ([self moreToSee]) {
        CGRect rect = CGRectZero;
        rect.size = _textview.bounds.size;
        rect.origin.y = _textview.contentOffset.y + rect.size.height;

        NSLog(@"pageDownOnInput: Scrolling to rect %@", NSStringFromCGRect(rect));
        _nowcontentscrolling = YES;
        inAnimatedScrollToBottom = NO;
        [_textview scrollRectToVisible:rect animated:YES];
        _textview.scrollEnabled = NO;
        _textview.scrollEnabled = YES;
		return YES;
	}

    [self scrollTextViewToBottomAnimate:YES];
	return NO;
}

- (BOOL) moreToSee {
    NSUInteger lastVisible = [self lastVisible];

    if (lastVisible && _textview.layoutManager.numberOfGlyphs)
    {
        if (lastVisible > _lastSeenCharacterIndex)
            _lastSeenCharacterIndex = lastVisible;
        if (_lastSeenCharacterIndex >= _textview.layoutManager.numberOfGlyphs - 1) {
            //            NSLog(@"No unseen text");
            return NO;
        } else {
            //            NSLog(@"%ld unseen glyphs", _textview.layoutManager.numberOfGlyphs - 1 - lastSeenCharacterIndex);
        }
        return YES;
    }

    return NO;
}

- (NSUInteger)lastVisible {
    CGPoint bottomright = CGPointMake(_textview.bounds.size.width, _textview.contentOffset.y + _textview.bounds.size.height - _textview.contentInset.bottom);

    NSUInteger lastVisible = [_textview.layoutManager characterIndexForPoint:bottomright inTextContainer:_textview.textContainer fractionOfDistanceBetweenInsertionPoints:NULL];
    return lastVisible;
}

- (void) scrollTextViewToBottomAnimate:(BOOL)animate {
//    NSLog(@"scrollTextViewToBottomAnimate %@", animate ? @"YES" : @"NO");
    if (_textview.text.length == 0)
        return;

    if (self.superviewAsFrameView.inOrientationAnimation)
        return;

    if (animate) {
        inAnimatedScrollToBottom = YES;
        _nowcontentscrolling = YES;
        NSRange range = NSMakeRange(_textview.text.length, 0);
        [_textview scrollRangeToVisible:range];
        // an iOS bug, see https://stackoverflow.com/a/20989956/971070
        _textview.scrollEnabled = NO;
        _textview.scrollEnabled = YES;
    } else {
        _textview.contentOffset = CGPointMake(_textview.contentOffset.x, _textview.contentSize.height - self.frame.size.height);
        NSUInteger lastVisible = [self lastVisible];
        if (lastVisible < self.textview.text.length - 1) {
        // Last visibile character is not the last character in the text. We have not, in fact, scrolled to the bottom. Retrying.
            if (recursionDepth > 100) {
                // Give up after 100 attempts
                recursionDepth = 0;
                [_textview scrollRangeToVisible:NSMakeRange(_textview.text.length - 1, 1)];
                if (self.inputfield)
                    [self placeInputField:self.inputfield holder:self.inputholder];
                return;
            }
            recursionDepth++;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void){
                [self scrollTextViewToBottomAnimate:NO];
            });
        } else {
            recursionDepth = 0;
            if (self.inputfield)
                [self placeInputField:self.inputfield holder:self.inputholder];
        }
    }
}

// Only called when orientation changes. We try to prevent excessive attempts to
// retain scroll position at bottom during animation
- (void) preserveScrollPosition {
    if (self.superviewAsFrameView.inOrientationAnimation)
        return;
    storedAtBottom = [self scrolledToBottom];
    storedAtTop = (_textview.contentOffset.y == 0);
    lastVisibleGlyph = [self lastVisible];
}

// Called when orientation change is finished
- (void) restoreScrollPosition {
    if (storedAtBottom) {
        [self scrollTextViewToBottomAnimate:NO];
    } else if (storedAtTop) {
        _textview.contentOffset = CGPointMake(_textview.contentOffset.x, 0);
    } else if (lastVisibleGlyph && lastVisibleGlyph <= _textview.text.length) {
        [_textview scrollRangeToVisible:NSMakeRange(lastVisibleGlyph, 1)];
    }
    if (self.inputfield)
        [self placeInputField:self.inputfield holder:self.inputholder];
}

- (BOOL) scrolledToBottom {
    return (_textview.contentOffset.y + 5 >= _textview.contentSize.height - _textview.frame.size.height);
}

- (void) setMoreFlag:(BOOL)flag {
	if (self.morewaiting == flag)
		return;

	/* NoMorePrompt is a preference that I decided to drop.
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL usemore = ![defaults boolForKey:@"NoMorePrompt"];
     if (!usemore)
     return;
     */

    self.morewaiting = flag;
    if (flag) {
        _moreview.alpha = 0;
        _moreview.hidden = NO;
        GlkWinBufferView __weak *weakSelf = self;
        [UIView animateWithDuration:0.5
                         animations:^{ weakSelf.moreview.alpha = 0.5; } ];
    }
    else {
        GlkWinBufferView __weak *weakSelf = self;
        [UIView animateWithDuration:0.5
                         animations:^{ weakSelf.moreview.alpha = 0; }
                         completion:^(BOOL finished) { weakSelf.moreview.hidden = YES; } ];
    }
}

/* Either the text field is brand-new, or last cycle's text field needs to be adjusted for a new request. Add it as a subview of the textview (if necessary), and move it to the right place.
*/
- (void) placeInputField:(UITextField *)field holder:(UIScrollView *)holder {
	CGRect box = [self placeForInputField];
//	NSLog(@"WBV: input field goes to %@", StringFromRect(box));

	field.frame = CGRectMake(0, 0, box.size.width, box.size.height);
	holder.contentSize = box.size;
	holder.frame = box;
	if (!holder.superview)
		[_textview addSubview:holder];
}

/* UIScrollView delegate methods: */

- (void) scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    _nowcontentscrolling = NO;
    if (inAnimatedScrollToBottom && ![self scrolledToBottom]) {
        // Did not actually scroll to bottom. Retrying.
        inAnimatedScrollToBottom = NO;
        [self scrollTextViewToBottomAnimate:NO];
    }
    inAnimatedScrollToBottom = NO;
//    /* If the scroll animation left us below the desired bottom edge, we'll extend the content height to include it. But only temporarily! This is to avoid jerkiness when the player scrolls to recover. */
//    CGFloat offset = (_textview.contentOffset.y + _textview.bounds.size.height) - _textview.contentSize.height;
//    if (offset > 1) {
//        CGSize size = _textview.contentSize;
//        size.height += offset;
//        _textview.contentSize = size;
//    }

    [self setMoreFlag:[self moreToSee]];
}

- (void) scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!_nowcontentscrolling) {
        inAnimatedScrollToBottom = NO;
        [self setMoreFlag:[self moreToSee]];
    }
}


- (CGRect) placeForInputField {
    CGRect box;

    CGFloat totalwidth = _textview.bounds.size.width;
    NSUInteger glyphs = _textview.text.length;

    // If textview is empty
    if (!glyphs) {
        box.origin.x = self.styleset.margins.left + self.viewmargin.left;
        box.size.width = totalwidth - self.styleset.margintotal.width;
        box.origin.y = 0;
        box.size.height = 24;
        return box;
    }

    UITextPosition *start = [_textview positionFromPosition:_textview.endOfDocument inDirection:UITextLayoutDirectionLeft offset:1];
    UITextRange *textRange = [_textview textRangeFromPosition:start toPosition:_textview.endOfDocument];

    CGRect fragmentRect = [_textview firstRectForRange:textRange];

    CGFloat ptx = CGRectGetMaxX(fragmentRect);
    if (ptx >= totalwidth * 0.75)
        ptx = totalwidth * 0.75;

    box.origin.x = ptx;
    box.size.width = (totalwidth - self.styleset.margins.right) - ptx;
    box.origin.y = fragmentRect.origin.y;
    box.size.height = fragmentRect.size.height;

    return box;
}

- (void) updateFromUIState:(NSDictionary *)state {
    [super updateFromUIState:state];
    NSLog(@"GlkWinBufferView %@ updateFromUIState", self.tagobj);

    NSNumber *lastSeen = state[@"lastSeenCharacterIndex"];
    if (lastSeen)
        _lastSeenCharacterIndex = lastSeen.integerValue;

    if (_textview) {
        NSNumber *location = state[@"selectionLoc"];
        NSNumber *length = state[@"selectionLen"];
        if (location && length) {
            _textview.selectedRange = NSMakeRange(location.integerValue, length.integerValue);
        }
        NSNumber *atBottomNumber = state[@"scrolledToBottom"];
        if (atBottomNumber && atBottomNumber.intValue) {
            [self scrollTextViewToBottomAnimate:NO];
            NSLog(@"GlkWinBufferView updateFromUIState: scrolling to bottom");
        } else {
            NSNumber *contentOffsetY = state[@"contentOffsetY"];
            if (contentOffsetY) {
                CGPoint contentOffset = _textview.contentOffset;
                contentOffset.y = contentOffsetY.floatValue;
                _textview.contentOffset = contentOffset;
            }
        }
    } else {
        NSLog(@"GlkWinBufferView: updateFromUIState found no textview!");
    }
}

@end
